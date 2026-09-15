require "rails_helper"
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe PublicationPreflight, type: :model do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  def prepared_context
    now = Time.current.change(usec: 0) - 5
    repository = Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
    version = publish_workflow
    task = Task.create!(repository:, sequence: 1, title: "Model preflight", task_input_schema_version: "1",
      approved_brief: "Verify durable preflight persistence.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
    advance_to_publication(task:, version:, candidate_sha: "a" * 40, now:)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "model-preflight-claim", now:)
    preflight = described_class.create!(repository:, task:, prepared_attempt: attempt,
      current_owner_attempt: attempt, candidate_sha: "a" * 40, remote: "origin", base_ref: "refs/heads/main",
      prepared_at: now)
    { now:, repository:, task:, attempt:, preflight: }
  end

  def persisted_summary
    context = prepared_context
    error = { "category" => "transient", "code" => "publication_preflight_state_uncertain",
      "message" => "Observation unavailable", "retryable" => true }
    preflight = context.fetch(:preflight)
    preflight.update!(state: "unknown", error:, reconciled_at: context.fetch(:now) + 1)
    resource = Api::V2::Serializer.publication_preflight(preflight.reload)
    [ preflight.error, context.fetch(:task).publication_preflights.active.ids,
      context.fetch(:task).publication_preflights.unresolved.ids, preflight.id,
      Kos::Cli::SchemaRegistry.new(version: "2").valid?("resources.json", "publication_preflight", resource) ]
  end

  def rejected?
    yield
    false
  rescue ActiveRecord::StatementInvalid
    true
  end

  def database_guard_summary
    context = prepared_context
    preflight = context.fetch(:preflight)
    immutable = rejected? { preflight.update_columns(candidate_sha: "b" * 40) }
    malformed = rejected? do
      preflight.update_columns(state: "unknown", error: nil, reconciled_at: context.fetch(:now) + 1)
    end
    duplicate = rejected? do
      described_class.create!(context.slice(:repository, :task).merge(prepared_attempt: context.fetch(:attempt),
        current_owner_attempt: context.fetch(:attempt), candidate_sha: "a" * 40, remote: "origin",
        base_ref: "refs/heads/main", prepared_at: context.fetch(:now)))
    end
    scoped_owner = rejected? { preflight.update_column(:current_owner_attempt_id, SecureRandom.uuid) }
    preflight.reload
    observed = { state: "reconciled", observation_owner_attempt: context.fetch(:attempt),
      observed_remote_oid: "b" * 40, observation_digest: "sha256:#{'c' * 64}",
      observed_at: context.fetch(:now) + 1, reconciled_at: context.fetch(:now) + 1 }
    preflight.update!(observed)
    changed_observation = rejected? { preflight.update_column(:observed_remote_oid, "d" * 40) }
    reconciled_same_owner = rejected? { preflight.update_column(:current_owner_attempt_id, context.fetch(:attempt).id) }
    bad_binding = rejected? do
      preflight.update_columns(state: "consumed", publication_id: SecureRandom.uuid,
        consumed_at: context.fetch(:now) + 2)
    end
    [ immutable, malformed, duplicate, scoped_owner, changed_observation, reconciled_same_owner, bad_binding ]
  end

  it "round trips a closed unknown error and exposes unresolved lifecycle scopes" do
    summary = persisted_summary
    expect(summary.values_at(0, 1, 2, 4)).to eq([ summary.first, [ summary.fetch(3) ], [ summary.fetch(3) ], true ])
  end


  it "enforces intent, lifecycle, uniqueness, scope, adoption, and consumption constraints" do
    expect(database_guard_summary).to eq([ true, true, true, true, true, false, true ])
  end
end
