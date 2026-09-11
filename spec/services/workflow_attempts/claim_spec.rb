require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowAttempts::Claim, :aggregate_failures do
  include WorkflowCatalogHelpers

  let(:digest) { "sha256:#{'a' * 64}" }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Own workflow step", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end
  let(:started_at) { Time.utc(2026, 9, 11, 12) }

  def claim(expected_lock_version: task.reload.lock_version, now: started_at, owner_id: "orchestrator-1")
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id:, lease_seconds: 300,
      expected_lock_version:, idempotency_key: "claim-key-#{SecureRandom.hex(4)}", now:)
  end

  def manifest(attempt, outcome)
    { "schema_version" => "1", "attempt_id" => attempt.id, "input_context_digest" => digest,
      "outcome" => outcome, "artifacts" => [] }
  end

  def freeze_context(attempt)
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
  end

  def renew(attempt, fencing_token: 1, expected_lock_version: 1, lease_seconds: 120, now: started_at + 60)
    WorkflowAttempts::Renew.call(repository:, attempt_id: attempt.id, fencing_token:,
      expected_lock_version:, lease_seconds:, now:)
  end

  def finish(attempt, state)
    WorkflowAttempts::Finish.call(repository:, attempt_id: attempt.id, fencing_token: 1,
      expected_lock_version: 1, manifest: manifest(attempt, state), state:, now: started_at + 1)
  end

  def reconcile(attempt, observed_state: "no_effect", expected_lock_version: 1, now: started_at + 301)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state:,
      evidence_digest: digest, expected_lock_version:, now:)
  end

  def failed_summary
    attempt = claim
    freeze_context(attempt)
    workflow_state_id = task.workflow_state_id
    result = finish(attempt, "failed")
    [ result.state, result.lease_expires_at, task.reload.active_attempt_id, task.workflow_state_id,
      task.status, TaskArtifact.count, workflow_state_id ]
  end

  def reconciliation_replacement_summary
    attempt = claim
    reconciled_at = started_at + 301
    result = reconcile(attempt, now: reconciled_at)
    replacement = claim(expected_lock_version: task.reload.lock_version, now: reconciled_at + 1)
    [ result.state, result.reconciliation_state, result.reconciliation_evidence_digest, result.reconciled_at,
      replacement.fencing_token, task.reload.active_attempt_id, replacement.id, reconciled_at ]
  end

  def expect_different_reconciliation_to_fail(attempt)
    expect {
      reconcile(attempt, observed_state: "worktree_materialized", expected_lock_version: 2, now: started_at + 302)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
  end

  it "claims an executable step with a bounded first fencing token" do
    attempt = claim

    expect([ attempt.fencing_token, attempt.heartbeat_at, attempt.lease_expires_at,
      task.reload.active_attempt_id, task.lock_version ])
      .to eq([ 1, started_at, started_at + 300, attempt.id, 1 ])
  end

  it "rejects another claim until the started attempt is reconciled" do
    claim

    expect { claim }.to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
  end

  it "renews from the current heartbeat without changing the task lock" do
    attempt = claim
    heartbeat = started_at + 60
    renew(attempt, now: heartbeat)
    expect([ attempt.reload.heartbeat_at, attempt.lease_expires_at, task.reload.lock_version ])
      .to eq([ heartbeat, heartbeat + 120, 1 ])
  end

  it "gives stale fencing precedence over an expired lease" do
    attempt = claim

    expect {
      renew(attempt, fencing_token: 2, lease_seconds: 30, now: started_at + 301)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("fencing_token_stale") }
  end

  it "treats the exact expiry time as lease loss" do
    attempt = claim

    expect {
      renew(attempt, lease_seconds: 30, now: started_at + 300)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("lease_expired") }
  end

  it "fails an attempt without advancing workflow or registering artifacts" do
    summary = failed_summary
    expect(summary).to eq([ "failed", nil, nil, summary.last, "open", 0, summary.last ])
  end

  it "marks the task blocked when an attempt needs human input" do
    attempt = claim
    freeze_context(attempt)
    finish(attempt, "needs_human")
    expect(task.reload.status).to eq("blocked")
  end

  it "requires a matching frozen context before controlled completion" do
    attempt = claim

    expect {
      finish(attempt, "failed")
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("context_unavailable") }
  end

  it "reconciles expiry with immutable evidence and permits the next token" do
    summary = reconciliation_replacement_summary
    expect(summary.values_at(0, 1, 2, 3, 4, 5))
      .to eq([ "interrupted", "no_effect", digest, summary.last, 2, summary.fetch(6) ])
  end

  it "rejects reconciliation before lease expiry" do
    attempt = claim

    expect {
      reconcile(attempt, now: started_at + 299)
    }.to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
  end

  it "returns matching interrupted evidence and rejects different evidence" do
    attempt = claim
    result = reconcile(attempt)
    repeated = reconcile(attempt, expected_lock_version: 2, now: started_at + 302)
    expect(repeated).to eq(result)
    expect_different_reconciliation_to_fail(attempt)
  end

  it "rejects the old owner after reconciliation and replacement" do
    attempt = claim
    reconcile(attempt)
    claim(expected_lock_version: 2, now: started_at + 302)
    expect { renew(attempt, expected_lock_version: 3, now: started_at + 303) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("fencing_token_stale") }
  end
end
