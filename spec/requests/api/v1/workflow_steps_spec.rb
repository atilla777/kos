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
    Task.create!(repository:, sequence: 1, title: "Complete API step", task_type: quick_fix_task_type,
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
end
