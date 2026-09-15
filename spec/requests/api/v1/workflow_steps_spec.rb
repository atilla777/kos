require "digest"
require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 workflow step completion", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "step-test-token"
    example.run
  ensure
    ENV["KOS_API_TOKEN"] = previous
  end

  let(:digest) { "sha256:#{'a' * 64}" }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Complete API step", task_input_schema_version: "1",
      approved_brief: "Complete the approved API step.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def start_attempt
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator-1",
      lease_seconds: 300, expected_lock_version: 0, idempotency_key: "claim-step-key")
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    attempt
  end

  def document
    { "schema_version" => "1", "type" => "document", "state" => "produced", "producer" => "workflow-step",
      "metadata" => { "kind" => "document", "path" => "tasks/#{task.number}/implementation-plan.md",
        "commit_sha" => "a" * 40, "content_digest" => digest } }
  end

  def completion_body(attempt, artifacts: [ document ])
    { "task_number" => task.number, "to_status" => "development",
      "result_manifest" => { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => digest, "outcome" => "succeeded", "artifacts" => artifacts },
      "preconditions" => { "expected_lock_version" => task.reload.lock_version,
        "attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token } }
  end

  def start_review_attempt(post_observation: :fresh)
    now = Time.current.change(usec: 0)
    development = task.workflow_version.workflow_states.find_by!(identifier: "development")
    review = task.workflow_version.workflow_states.find_by!(identifier: "review")
    task.update!(workflow_state: development)
    producer = WorkflowAttempt.create!(repository:, task:, workflow_state: development, owner_id: "developer",
      idempotency_key: "candidate-attempt", fencing_token: 1, started_at: now, heartbeat_at: now,
      lease_expires_at: now + 300, input_context: { "schema_version" => "1" }, input_context_digest: digest)
    task.update!(active_attempt: producer)
    task.update!(active_attempt: nil, workflow_state: review)
    producer.update!(state: "succeeded", lease_expires_at: nil, completed_at: now,
      result_manifest: { "schema_version" => "1", "attempt_id" => producer.id,
        "input_context_digest" => digest, "outcome" => "succeeded", "artifacts" => [] },
      completed_transition: task.workflow_version.workflow_transitions.find_by!(from_state: development,
        to_state: review))
    candidate_sha = "b" * 40
    TaskArtifact.create!(repository:, task:, workflow_attempt: producer, artifact_type: "candidate",
      state: "produced", producer: "workflow-step", metadata: { "kind" => "candidate",
        "candidate_sha" => candidate_sha, "task_trailer" => task.number })
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "reviewer",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version, idempotency_key: "review-claim")
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, git_common_dir_digest: digest, head_sha: candidate_sha,
      confirmed_at: now)
    reservation.update!(observed_state: "clean",
      observation_digest: Kos::WorktreeObservation.digest(repository_id: repository.id,
      reservation_id: reservation.id, fencing_token: attempt.fencing_token, path: reservation.path,
      branch: reservation.branch, state: "clean", head_sha: candidate_sha,
      git_common_dir_digest: reservation.git_common_dir_digest))
    task.reload.update!(worktree_reservation: reservation)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
    attempt.reload
    reservation.reload
    unless post_observation == :none
      context_digest = attempt.input_context_digest if post_observation == :fresh
      reservation.update!(observed_state: "clean",
        observation_digest: Kos::WorktreeObservation.digest(repository_id: repository.id,
          reservation_id: reservation.id, fencing_token: attempt.fencing_token, path: reservation.path,
          branch: reservation.branch, state: "clean", head_sha: candidate_sha,
          git_common_dir_digest: reservation.git_common_dir_digest, input_context_digest: context_digest))
    end
    [ attempt, candidate_sha ]
  end

  def review_completion_body(attempt, candidate_sha)
    artifact = JSON.parse(JSON.generate({ "schema_version" => "1", "type" => "review", "state" => "approved",
      "producer" => "workflow-step", "metadata" => { "kind" => "review", "candidate_sha" => candidate_sha,
        "verdict" => "approved", "review_attempt_id" => attempt.id } }))
    body = completion_body(attempt, artifacts: [ artifact ]).merge("to_status" => "publication")
    body.fetch("result_manifest")["input_context_digest"] = attempt.input_context_digest
    body
  end

  def post_completion(body, key: "complete-step-key", path_number: task.number)
    request_document = { "schema_version" => "1", "command" => "step.complete",
      "repository_id" => repository.id, "body" => body }
    post "/api/v1/repositories/#{repository.id}/tasks/#{path_number}/steps/complete",
      params: request_document, headers: { "Authorization" => "Bearer step-test-token",
        "Idempotency-Key" => key }, as: :json
    JSON.parse(response.body)
  end

  def verification_for(artifacts)
    canonical = WorkflowCatalog::CanonicalDefinition.canonical_json(artifacts)
    RepositoryEvidence::VerifyArtifacts::Verification.new(repository.id, task.number,
      "sha256:#{Digest::SHA256.hexdigest(canonical)}")
  end

  def successful_replay_summary
    attempt = start_attempt
    body = completion_body(attempt)
    allow(RepositoryEvidence::VerifyArtifacts).to receive(:call).and_return(verification_for(body.dig(
      "result_manifest", "artifacts")))
    first = post_completion(body)
    second = post_completion(body)
    [ response.status, first.dig("data", "task", "workflow_status"),
      second.dig("data", "artifacts", 0, "id"), first.dig("data", "artifacts", 0, "id"),
      TaskArtifact.count, IdempotencyRecord.where(command: "step.complete").count,
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", second) ]
  end

  def invalid_replay_summary
    attempt = start_attempt
    body = completion_body(attempt, artifacts: [])
    first = post_completion(body)
    second = post_completion(body)
    [ first.dig("error", "code"), second.dig("error", "code"), attempt.reload.state,
      TaskArtifact.count, IdempotencyRecord.where(command: "step.complete").count ]
  end

  def review_completion_summary
    attempt, candidate_sha = start_review_attempt
    body = review_completion_body(attempt, candidate_sha)
    allow(RepositoryEvidence::VerifyArtifacts).to receive(:call).and_return(verification_for(body.dig(
      "result_manifest", "artifacts")))
    result = post_completion(body, key: "complete-review-key")
    [ response.status, result.dig("data", "task", "workflow_status"),
      result.dig("data", "artifacts", 0, "metadata", "candidate_sha"),
      result.dig("data", "artifacts", 0, "metadata", "review_attempt_id"), candidate_sha, attempt.id ]
  end

  def review_without_post_observation_code
    attempt, candidate_sha = start_review_attempt(post_observation: :none)
    body = review_completion_body(attempt, candidate_sha)
    allow(RepositoryEvidence::VerifyArtifacts).to receive(:call).and_return(verification_for(body.dig(
      "result_manifest", "artifacts")))
    post_completion(body, key: "review-without-post-observation").dig("error", "code")
  end

  def review_with_replayed_pre_observation_code
    attempt, candidate_sha = start_review_attempt(post_observation: :replayed)
    body = review_completion_body(attempt, candidate_sha)
    allow(RepositoryEvidence::VerifyArtifacts).to receive(:call).and_return(verification_for(body.dig(
      "result_manifest", "artifacts")))
    post_completion(body, key: "review-with-replayed-observation").dig("error", "code")
  end

  it "completes a step and replays its task and artifacts after lease release" do
    summary = successful_replay_summary
    expect(summary).to eq([ 200, "development", summary.fetch(3), summary.fetch(3), 1, 1, true ])
  end

  it "rejects path and body task mismatch before evidence verification" do
    result = post_completion(completion_body(start_attempt), path_number: "KOS-000002")
    expect([ response.status, result.dig("error", "code"), TaskArtifact.count ])
      .to eq([ 400, "malformed_input", 0 ])
  end

  it "returns and replays invalid artifact failures without partial state" do
    expect(invalid_replay_summary).to eq([ "invalid_artifact", "invalid_artifact", "started", 0, 1 ])
  end


  it "registers an exact-candidate review and returns its publication transition" do
    summary = review_completion_summary
    expect(summary).to eq([ 200, "publication", summary.fetch(4), summary.fetch(5), *summary.last(2) ])
  end


  it "rejects review completion until an observation is reconciled after context capture" do
    expect(review_without_post_observation_code).to eq("invalid_artifact")
  end


  it "rejects replayed pre-context observation evidence" do
    expect(review_with_replayed_pre_observation_code).to eq("invalid_artifact")
  end
end
