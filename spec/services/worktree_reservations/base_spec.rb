require "rails_helper"
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorktreeReservations::Base, :aggregate_failures do
  include WorkflowCatalogHelpers

  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:task) do
    type = quick_fix_task_type
    version = publish_workflow
    Task.create!(repository:, sequence: 1, title: "Reserve worktree", task_type: type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end
  let(:started_at) { Time.utc(2026, 9, 11, 14) }
  let(:head_sha) { "b" * 40 }
  let(:digest) { "sha256:#{'a' * 64}" }

  def claim(now: started_at)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "orchestrator",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "claim-#{SecureRandom.hex(4)}", now:)
  end

  def reserve(attempt, path: "/tmp/worktrees/#{task.number}", **overrides)
    WorktreeReservations::Reserve.call(repository:, task_number: task.number,
      branch: "kos/task-#{task.number}", path:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version,
      now: started_at + 1, **overrides)
  end

  def confirm(reservation, attempt, **overrides)
    WorktreeReservations::Confirm.call(repository:, reservation_id: reservation.id,
      git_common_dir_digest: "sha256:#{Digest::SHA256.hexdigest(repository.git_common_dir)}", head_sha:,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: started_at + 2, **overrides)
  end

  def observe(operation, reservation, attempt, observed_state:, observed_head: nil, now: started_at + 3)
    operation.call(repository:, reservation_id: reservation.id, observed_state:, head_sha: observed_head,
      evidence_digest: digest, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
  end

  def release_summary
    attempt = claim
    reservation = confirm(reserve(attempt), attempt)
    pending = observe(WorktreeReservations::Release, reservation, attempt,
      observed_state: "clean", observed_head: head_sha)
    released = observe(WorktreeReservations::Release, reservation, attempt,
      observed_state: "absent", now: started_at + 4)
    [ pending.state, released.state, released.released_at, task.reload.worktree_reservation_id ]
  end

  def adoption_summary
    first = claim
    reservation = reserve(first)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: first.id, observed_state: "worktree_materialized",
      evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: started_at + 301)
    second = claim(now: started_at + 302)
    [ reservation.reload, first, second ]
  end

  def stale_reconciliation(reservation, attempt)
    WorktreeReservations::Reconcile.call(repository:, reservation_id: reservation.id, observed_state: "clean",
      head_sha:, evidence_digest: digest, attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: started_at + 303)
  end

  def release_pending_reservation(attempt)
    reservation = confirm(reserve(attempt), attempt)
    observe(WorktreeReservations::Release, reservation, attempt, observed_state: "clean", observed_head: head_sha)
    reservation
  end

  def rebind_pending_head(reservation, attempt)
    observe(WorktreeReservations::Reconcile, reservation, attempt, observed_state: "clean",
      observed_head: "c" * 40)
  end

  it "reserves and confirms the task-derived allocation" do
    attempt = claim
    reservation = reserve(attempt)
    confirmed = confirm(reservation, attempt)

    expect([ confirmed.state, confirmed.head_sha, task.reload.worktree_reservation_id, task.lock_version ])
      .to eq([ "confirmed", head_sha, reservation.id, 2 ])
  end

  it "rejects a noncanonical path before persistence" do
    attempt = claim

    expect { reserve(attempt, path: "/tmp/worktrees/../escape") }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("malformed_input") }
    expect(WorktreeReservation.count).to eq(0)
  end

  it "rejects confirmation from another Git common directory" do
    attempt = claim
    reservation = reserve(attempt)

    expect { confirm(reservation, attempt, git_common_dir_digest: digest) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
    expect(reservation.reload.state).to eq("reserved")
  end

  it "uses release_pending before recording observed absence" do
    expect(release_summary)
      .to eq([ "release_pending", "released", started_at + 4, nil ])
  end

  it "preserves dirty allocation instead of releasing it" do
    attempt = claim
    reservation = confirm(reserve(attempt), attempt)
    observed = observe(WorktreeReservations::Release, reservation, attempt, observed_state: "dirty")

    expect([ observed.state, observed.observed_state, task.reload.worktree_reservation_id ])
      .to eq([ "confirmed", "dirty", reservation.id ])
  end

  it "requires release_pending before release records absence" do
    attempt = claim
    reservation = confirm(reserve(attempt), attempt)

    expect { observe(WorktreeReservations::Release, reservation, attempt, observed_state: "absent") }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
    expect(reservation.reload.state).to eq("confirmed")
  end

  it "does not rebind a pending cleanup intent to another HEAD" do
    attempt = claim
    reservation = release_pending_reservation(attempt)

    expect { rebind_pending_head(reservation, attempt) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_transition") }
    expect(reservation.reload.head_sha).to eq(head_sha)
  end

  it "adopts an unresolved reservation with the next fencing token" do
    reservation, first, second = adoption_summary

    expect([ reservation.workflow_attempt_id, reservation.fencing_token, second.fencing_token ])
      .to eq([ second.id, 2, 2 ])
    expect { stale_reconciliation(reservation, first) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("fencing_token_stale") }
  end

  it "prevents backward and post-release updates at the database boundary" do
    attempt = claim
    reservation = confirm(reserve(attempt), attempt)

    expect { reservation.update!(state: "reserved", git_common_dir_digest: nil, head_sha: nil, confirmed_at: nil) }
      .to raise_error(ActiveRecord::StatementInvalid, /worktree reservation/)
  end

  it "requires a matching clean observation for release_pending at the database boundary" do
    attempt = claim
    reservation = confirm(reserve(attempt), attempt)

    expect { reservation.update!(state: "release_pending", observed_state: "dirty", observation_digest: digest) }
      .to raise_error(ActiveRecord::StatementInvalid, /invalid worktree reservation lifecycle/)
  end

  it "keeps release_pending HEAD immutable at the database boundary" do
    attempt = claim
    reservation = release_pending_reservation(attempt)

    expect { reservation.update!(head_sha: "c" * 40) }
      .to raise_error(ActiveRecord::StatementInvalid, /confirmation identity is immutable/)
  end
end
