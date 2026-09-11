require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe "API v1 workflow attempts", :aggregate_failures, type: :request do
  include WorkflowCatalogHelpers
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    previous = ENV["KOS_API_TOKEN"]
    ENV["KOS_API_TOKEN"] = "attempt-test-token"
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
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Run workflow", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def headers(key)
    { "Authorization" => "Bearer attempt-test-token", "Accept" => "application/json",
      "Idempotency-Key" => key }
  end

  def request_document(command, body, repository_id: repository.id)
    { "schema_version" => "1", "command" => command, "repository_id" => repository_id, "body" => body }
  end

  def claim(key: "attempt-claim-key", body: nil)
    body ||= { "task_number" => task.number, "owner_id" => "orchestrator-1", "lease_seconds" => 300,
      "preconditions" => { "expected_lock_version" => task.reload.lock_version } }
    post "/api/v1/repositories/#{repository.id}/tasks/#{task.number}/attempts/claim",
      params: request_document("attempt.claim", body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def leased_body(attempt, extra = {})
    extra.merge("preconditions" => { "expected_lock_version" => task.reload.lock_version,
      "attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token })
  end

  def confirm_worktree(attempt)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, git_common_dir_digest: digest, head_sha: "b" * 40,
      confirmed_at: Time.current)
    task.reload.update!(worktree_reservation: reservation)
  end

  def manifest(attempt, outcome)
    { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "outcome" => outcome, "artifacts" => [] }
  end

  def post_attempt(attempt, operation, body, key: "attempt-#{operation}-key")
    path_operation = operation == "needs_human" ? "needs-human" : operation
    command = if operation == "needs_human"
      "attempt.needs_human"
    elsif operation == "step-context"
      "step.context"
    else
      "attempt.#{operation}"
    end
    post "/api/v1/repositories/#{repository.id}/attempts/#{attempt.id}/#{path_operation}",
      params: request_document(command, body), headers: headers(key), as: :json
    JSON.parse(response.body)
  end

  def claim_replay_summary
    body = { "task_number" => task.number, "owner_id" => "orchestrator-1", "lease_seconds" => 300,
      "preconditions" => { "expected_lock_version" => 0 } }
    first = claim(body:)
    second = claim(body:)
    [ response.status, first.dig("data", "id"), second.dig("data", "id"), WorkflowAttempt.count,
      IdempotencyRecord.count, Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", second) ]
  end

  def renewal_replay_summary
    attempt = WorkflowAttempt.find(claim.dig("data", "id"))
    body = leased_body(attempt, "lease_seconds" => 600)
    first = post_attempt(attempt, "renew", body)
    second = travel_to(11.minutes.from_now) { post_attempt(attempt, "renew", body) }
    [ response.status, second.dig("data", "lease_expires_at"), first.dig("data", "lease_expires_at"),
      IdempotencyRecord.count ]
  end

  def failed_attempt_summary
    attempt = WorkflowAttempt.find(claim.dig("data", "id"))
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    result = post_attempt(attempt, "fail", leased_body(attempt, "result_manifest" => manifest(attempt, "failed")))
    [ response.status, result.dig("data", "state"), task.reload.status,
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", result) ]
  end

  def error_category_summary
    attempt = WorkflowAttempt.find(claim.dig("data", "id"))
    stale = leased_body(attempt, "lease_seconds" => 300)
    stale.fetch("preconditions")["fencing_token"] += 1
    stale_result = post_attempt(attempt, "renew", stale)
    context_result = post_attempt(attempt, "fail",
      leased_body(attempt, "result_manifest" => manifest(attempt, "failed")), key: "attempt-fail-key-2")
    [ stale_result.dig("error", "category"), stale_result.dig("error", "code"),
      context_result.dig("error", "category"), context_result.dig("error", "code") ]
  end

  def reconciliation_summary
    attempt = WorkflowAttempt.find(claim.dig("data", "id"))
    body = { "attempt_id" => attempt.id, "observed_state" => "repository_effect_pending",
      "evidence_digest" => digest, "expected_lock_version" => task.reload.lock_version }
    result = travel_to(6.minutes.from_now) { post_attempt(attempt, "reconcile", body) }
    [ response.status, result.dig("data", "state"), result.dig("data", "reconciliation_state"),
      result.dig("data", "reconciliation_evidence_digest"),
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", result) ]
  end

  def cross_repository_summary
    attempt = WorkflowAttempt.find(claim.dig("data", "id"))
    other = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "ALT",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/other.git", base_ref: "refs/heads/main")
    post "/api/v1/repositories/#{other.id}/attempts/#{attempt.id}/renew",
      params: request_document("attempt.renew", leased_body(attempt, "lease_seconds" => 300),
        repository_id: other.id), headers: headers("other-renew-key"), as: :json
    [ response.status, JSON.parse(response.body).dig("error", "code") ]
  end

  def terminal_replay_summary(operation, outcome)
    attempt = WorkflowAttempt.find(claim(key: "claim-for-#{operation}").dig("data", "id"))
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    body = leased_body(attempt, "result_manifest" => manifest(attempt, outcome))
    first = post_attempt(attempt, operation, body)
    second = post_attempt(attempt, operation, body)
    [ response.status, first.dig("data", "id"), second.dig("data", "id"), WorkflowAttempt.count,
      IdempotencyRecord.count ]
  end

  def reconciliation_replay_summary
    attempt = WorkflowAttempt.find(claim(key: "claim-for-reconcile").dig("data", "id"))
    body = { "attempt_id" => attempt.id, "observed_state" => "no_effect", "evidence_digest" => digest,
      "expected_lock_version" => task.reload.lock_version }
    first = travel_to(6.minutes.from_now) { post_attempt(attempt, "reconcile", body) }
    second = post_attempt(attempt, "reconcile", body)
    [ response.status, first.dig("data", "id"), second.dig("data", "id"), IdempotencyRecord.count ]
  end

  def context_expiry_replay_summary
    attempt = WorkflowAttempt.find(claim(key: "claim-for-context").dig("data", "id"))
    confirm_worktree(attempt)
    body = leased_body(attempt)
    first = post_attempt(attempt, "step-context", body, key: "step-context-key")
    second = travel_to(6.minutes.from_now) do
      post_attempt(attempt, "step-context", body, key: "step-context-key")
    end
    [ response.status, first.fetch("data"), second.fetch("data"),
      Kos::Cli::SchemaRegistry.new.valid?("commands.json", "result", second) ]
  end

  def context_new_key_summary
    attempt = WorkflowAttempt.find(claim(key: "claim-for-frozen-context").dig("data", "id"))
    confirm_worktree(attempt)
    body = leased_body(attempt)
    first = post_attempt(attempt, "step-context", body, key: "step-context-first-key")
    RuntimeConfig.current.update!(retrospective_enabled: true)
    second = post_attempt(attempt, "step-context", body, key: "step-context-second-key")
    [ first.fetch("data"), second.fetch("data"), second.dig("data", "retrospective_enabled") ]
  end

  it "claims once and replays the original HTTP 201 response" do
    summary = claim_replay_summary
    expect(summary.values_at(0, 1, 2, 3, 4, 5)).to eq([ 201, summary.fetch(1), summary.fetch(1), 1, 1, true ])
  end

  it "renews an active lease through the repository-scoped endpoint" do
    attempt_id = claim.dig("data", "id")
    attempt = WorkflowAttempt.find(attempt_id)
    result = post_attempt(attempt, "renew", leased_body(attempt, "lease_seconds" => 600))

    expect([ response.status, result.dig("data", "id"), result.dig("data", "state") ])
      .to eq([ 200, attempt.id, "started" ])
  end

  it "freezes context and replays it after lease expiry" do
    summary = context_expiry_replay_summary
    expect(summary).to eq([ 200, summary.fetch(1), summary.fetch(1), true ])
  end

  it "returns one frozen context for later idempotency keys" do
    summary = context_new_key_summary
    expect(summary).to eq([ summary.first, summary.first, false ])
  end

  it "replays a lease renewal after the lease has expired" do
    summary = renewal_replay_summary
    expect(summary).to eq([ 200, summary.fetch(2), summary.fetch(2), 2 ])
  end

  it "persists a failed manifest and returns a schema-valid terminal attempt" do
    expect(failed_attempt_summary).to eq([ 200, "failed", "open", true ])
  end

  it "maps fencing loss and missing context to their stable categories" do
    expect(error_category_summary)
      .to eq([ "lease_lost", "fencing_token_stale", "conflict", "context_unavailable" ])
  end

  it "rejects path and body identity mismatch before mutation" do
    body = { "task_number" => "KOS-000002", "owner_id" => "orchestrator-1", "lease_seconds" => 300,
      "preconditions" => { "expected_lock_version" => 0 } }
    result = claim(body:)

    expect([ response.status, result.dig("error", "code"), WorkflowAttempt.count ])
      .to eq([ 400, "malformed_input", 0 ])
  end

  it "reconciles an expired attempt and returns its durable observation" do
    expect(reconciliation_summary).to eq([ 200, "interrupted", "repository_effect_pending", digest, true ])
  end

  it "does not disclose an attempt from another repository" do
    expect(cross_repository_summary).to eq([ 404, "attempt_not_found" ])
  end


  %w[fail needs_human].each do |operation|
    it "replays attempt.#{operation} after terminalization" do
      outcome = operation == "needs_human" ? "needs_human" : "failed"
      summary = terminal_replay_summary(operation, outcome)
      expect(summary).to eq([ 200, summary.fetch(1), summary.fetch(1), 1, 2 ])
    end
  end

  it "replays attempt.reconcile after ownership release" do
    summary = reconciliation_replay_summary
    expect(summary).to eq([ 200, summary.fetch(1), summary.fetch(1), 2 ])
  end
end
