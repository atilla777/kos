require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe Publication, type: :model do
  include WorkflowCatalogHelpers

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Publication persistence", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end
  let(:attempt) do
    WorkflowAttempt.create!(repository:, task:, workflow_state: task.workflow_state, owner_id: "owner",
      idempotency_key: "publication-owner", fencing_token: 1, started_at: now, heartbeat_at: now,
      lease_expires_at: now + 5.minutes).tap { task.update!(active_attempt: _1) }
  end

  def now = (@now ||= Time.current.change(usec: 0))

  def publication
    @publication ||= begin
      record = task.publications.create!(repository:, prepared_attempt: attempt, current_owner_attempt: attempt,
        candidate_sha: "a" * 40, remote: "origin", base_ref: "refs/heads/main",
        expected_remote_oid: "b" * 40, prepared_at: now)
      task.update!(active_publication: record)
      record
    end
  end

  def observed_attributes(owner: attempt, reachable: false)
    { state: "reconciled", observation_owner_attempt: owner, observed_remote_tip: "b" * 40,
      candidate_reachable: reachable, observation_digest: "sha256:#{'c' * 64}", observed_at: now + 1,
      reconciled_at: now + 1 }
  end

  def bypass_observation(owner: attempt, observed_at: now + 1)
    observed_attributes(owner:, reachable: false).except(:observation_owner_attempt)
      .merge(observation_owner_attempt_id: owner.id, observed_at:)
  end

  def adopt_publication
    publication
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "publication_unknown",
      evidence_digest: "sha256:#{'d' * 64}", expected_lock_version: task.reload.lock_version,
      now: attempt.lease_expires_at + 1)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "replacement",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "replacement-claim", now: attempt.lease_expires_at + 2)
  end

  it "requires an observation owner with observed state" do
    expect { publication.update_columns(observed_attributes.except(:observation_owner_attempt)) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "requires no observation owner while prepared" do
    expect { publication.update_column(:observation_owner_attempt_id, attempt.id) }
      .to raise_error(ActiveRecord::StatementInvalid, /publications_observation_shape/)
  end

  it "rejects changing an observation to an owner from another task" do
    publication.update!(observed_attributes)
    expect { publication.update_column(:observation_owner_attempt_id, other_task_attempt.id) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "restricts candidate_reachable storage to SQLite booleans" do
    expect { described_class.where(id: publication.id).update_all(candidate_reachable: Arel.sql("2")) }
      .to raise_error(ActiveRecord::StatementInvalid, /publications_candidate_reachable_boolean/)
  end

  it "rejects a non-monotonic observation through a database bypass" do
    publication.update!(observed_attributes)

    expect { publication.update_column(:observed_at, now + 1) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "rejects an observation owner other than the current owner through a database bypass" do
    adopt_publication

    expect { publication.update_columns(bypass_observation(owner: attempt)) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "rejects an observation before preparation through a database bypass" do
    expect { publication.update_columns(bypass_observation(observed_at: publication.prepared_at - 1)) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "rejects an observation beyond the database clock skew through a database bypass" do
    expect { publication.update_columns(bypass_observation(observed_at: Time.current + 6.minutes)) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid publication observation update/)
  end

  it "preserves the historical observation owner during adoption" do
    publication.update!(observed_attributes)
    replacement = adopt_publication

    expect(publication.reload.attributes.values_at("current_owner_attempt_id", "observation_owner_attempt_id"))
      .to eq([ replacement.id, attempt.id ])
  end

  def other_task_attempt
    other_task = Task.create!(repository:, sequence: 2, title: "Other task", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
    WorkflowAttempt.create!(repository:, task: other_task, workflow_state: other_task.workflow_state,
      owner_id: "other-owner", idempotency_key: "other-publication-owner", fencing_token: 1,
      started_at: now, heartbeat_at: now, lease_expires_at: now + 5.minutes)
  end
end
