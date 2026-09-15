require "rails_helper"
require Rails.root.join("lib/kos/publication_preflight_evidence")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe PublicationPreflights::Prepare, :aggregate_failures do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  let(:now) { Time.current.change(usec: 0) }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Preflight publication", task_input_schema_version: "1",
      approved_brief: "Publish from a durable observation.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def candidate_sha = "a" * 40
  def observed_oid = "b" * 40

  def claim(owner: "publisher", at: now)
    advance_to_publication(task:, version:, candidate_sha:, now:) unless
      task.reload.workflow_state.identifier == "publication"
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: owner, lease_seconds: 300,
      expected_lock_version: task.reload.lock_version, idempotency_key: "claim-#{SecureRandom.hex(5)}", now: at)
  end

  def prepare(attempt)
    PublicationPreflights::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
  end

  def reconcile(preflight, attempt, observed_at: (now + 1).iso8601(6), digest: nil, current_time: now + 1)
    preflight.reload
    digest ||= publication_preflight_evidence(repository:, preflight:, attempt:,
      observed_remote_oid: observed_oid, observed_at:)
    PublicationPreflights::Reconcile.call(repository:, preflight_id: preflight.id,
      observed_remote_oid: observed_oid, observed_at:, evidence_digest: digest, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: current_time)
  end

  def consumed_summary
    attempt = claim
    preflight = reconcile(prepare(attempt), attempt)
    publication = Publications::PrepareObserved.call(repository:, preflight_id: preflight.id,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 2)
    [ preflight.reload.state, preflight.publication_id, publication.id,
      publication.expected_remote_oid, task.reload.active_publication_id ]
  end

  it "persists verified observation and atomically consumes it into a publication" do
    summary = consumed_summary
    expect(summary).to eq([ "consumed", summary.fetch(2), summary.fetch(2), observed_oid, summary.fetch(2) ])
  end

  it "rejects noncanonical evidence without partially resolving the intent" do
    attempt = claim
    preflight = prepare(attempt)

    expect { reconcile(preflight, attempt, digest: "sha256:#{'f' * 64}") }
      .to raise_error(OperationError) { expect(_1.code).to eq("invalid_transition") }
    expect(preflight.reload.state).to eq("prepared")
  end

  def recovery_summary
    attempt = claim
    preflight = prepare(attempt)
    error = { "category" => "transient", "code" => "publication_preflight_state_uncertain",
      "message" => "Observation result was lost", "retryable" => true }
    PublicationPreflights::Reconcile.call(repository:, preflight_id: preflight.id, unknown: error,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 1)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id,
      observed_state: "publication_unknown", evidence_digest: "sha256:#{'d' * 64}",
      expected_lock_version: task.reload.lock_version, now: attempt.lease_expires_at + 1)
    replacement = claim(owner: "replacement", at: attempt.lease_expires_at + 2)

    stale = begin
      reconcile(preflight, attempt)
    rescue OperationError => error
      error.code
    end
    recovered_at = attempt.lease_expires_at + 3
    reconciled = reconcile(preflight, replacement, observed_at: (now + 1).iso8601(6), current_time: recovered_at)
    [ preflight.reload.current_owner_attempt_id, replacement.id, stale, reconciled.state ]
  end

  it "records unknown, adopts it after recovery, and accepts only the current owner's evidence" do
    summary = recovery_summary
    expect(summary).to eq([ summary.fetch(1), summary.fetch(1), "fencing_token_stale", "reconciled" ])
  end

  def reconciled_recovery_summary
    attempt = claim
    preflight = reconcile(prepare(attempt), attempt)
    recovered_at = attempt.lease_expires_at + 1
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id,
      observed_state: "publication_unknown", evidence_digest: "sha256:#{'d' * 64}",
      expected_lock_version: task.reload.lock_version, now: recovered_at)
    replacement = claim(owner: "replacement", at: recovered_at + 1)

    publication = Publications::PrepareObserved.call(repository:, preflight_id: preflight.id,
      attempt_id: replacement.id, fencing_token: replacement.fencing_token,
      expected_lock_version: task.reload.lock_version, now: recovered_at + 2)
    preflight.reload.attributes.values_at("state", "current_owner_attempt_id", "publication_id") +
      [ replacement.id, publication.id ]
  end

  it "adopts a reconciled preflight so a replacement attempt can consume it" do
    summary = reconciled_recovery_summary
    expect(summary.values_at(0, 1, 2)).to eq([ "consumed", summary.fetch(3), summary.fetch(4) ])
  end
end
