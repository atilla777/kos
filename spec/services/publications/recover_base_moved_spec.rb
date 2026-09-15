require "rails_helper"
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe Publications::RecoverBaseMoved, :aggregate_failures do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  let(:now) { Time.current.change(usec: 0) }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:definition) { JSON.parse(File.read(Rails.root.join("workflows/quick-fix/1.0.2.json"))) }
  let(:version) { publish_workflow(definition) }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Recover moved base", task_input_schema_version: "1",
      approved_brief: "Recover the approved candidate after base movement.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def candidate_sha = "a" * 40
  def expected_oid = "b" * 40
  def moved_oid = "c" * 40

  def prepare_moved_publication
    publication, attempt = prepare_publication
    expect do
      Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
        observed_remote_tip: moved_oid, candidate_reachable: false, observed_at: now + 1.second,
        evidence_digest: "sha256:#{'e' * 64}", attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: now + 2.seconds)
    end.to raise_error(CommittedOperationError, /base ref moved/i)
    [ publication.reload, attempt.reload ]
  end

  def prepare_publication
    advance_to_publication(task:, version:, candidate_sha:, now:)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "publication-recovery-claim", now:)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, head_sha: candidate_sha,
      git_common_dir_digest: "sha256:#{'d' * 64}", confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    publication = Publications::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, expected_remote_oid: expected_oid,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    [ publication, attempt.reload ]
  end

  def recover(publication, attempt, **overrides)
    described_class.call(repository:, publication_id: publication.id, attempt_id: attempt.id,
      fencing_token: overrides.fetch(:fencing_token, attempt.fencing_token),
      expected_lock_version: overrides.fetch(:expected_lock_version, task.reload.lock_version),
      now: overrides.fetch(:now, now + 3.seconds))
  end

  it "atomically takes the pinned recovery edge without publication artifacts" do
    summary = recovery_summary
    expect(summary).to eq([ "base-synchronization", nil, "base-synchronization", "succeeded",
      summary.fetch(4), [], "superseded", 0 ])
  end

  def recovery_summary
    publication, attempt = prepare_moved_publication
    result = recover(publication, attempt)
    [ result.task.workflow_state.identifier, result.task.active_attempt_id, result.transition.to_state.identifier,
      attempt.reload.state, attempt.completed_transition_id, attempt.result_manifest.fetch("artifacts"),
      publication.reload.state, task.task_artifacts.where(workflow_attempt: attempt).count ]
  end

  it "allows a replacement publication attempt to recover immutable superseded evidence" do
    summary = replacement_recovery_summary
    expect(summary).to eq([ summary.first, "base-synchronization", "succeeded", "interrupted", true ])
  end

  def replacement_recovery_summary
    publication, attempt = prepare_moved_publication
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "no_effect",
      evidence_digest: "sha256:#{'f' * 64}", expected_lock_version: task.reload.lock_version,
      now: now + 301.seconds)
    replacement = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "replacement",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "publication-recovery-replacement", now: now + 302.seconds)
    context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: replacement.id,
      fencing_token: replacement.fencing_token, expected_lock_version: task.reload.lock_version,
      now: now + 302.seconds)

    result = recover(publication, replacement, now: now + 303.seconds)

    [ context.dig("publication", "publication_id"), result.task.workflow_state.identifier,
      replacement.reload.state, attempt.reload.state, publication.current_owner_attempt_id == attempt.id ]
  end

  it "rejects stale ownership without changing the recovery state" do
    publication, attempt = prepare_moved_publication

    expect { recover(publication, attempt, fencing_token: attempt.fencing_token + 1) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("fencing_token_stale") }
    expect([ task.reload.workflow_state.identifier, attempt.reload.state, publication.reload.state ])
      .to eq([ "publication", "started", "superseded" ])
  end

  it "rejects missing and unreconciled publication evidence" do
    expect(missing_and_unreconciled_codes).to eq(%w[publication_not_found invalid_transition])
  end

  def missing_and_unreconciled_codes
    publication, attempt = prepare_publication
    [ SecureRandom.uuid, publication.id ].map do |publication_id|
      described_class.call(repository:, publication_id:, attempt_id: attempt.id,
        fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
    rescue OperationError => error
      error.code
    end
  end

  it "rejects stale lock and expired lease preconditions" do
    publication, attempt = prepare_moved_publication
    stale = operation_code { recover(publication, attempt, expected_lock_version: task.lock_version - 1) }
    expired = operation_code { recover(publication, attempt, now: now + 301.seconds) }
    expect([ stale, expired, task.reload.workflow_state.identifier ])
      .to eq(%w[stale_lock_version lease_expired publication])
  end

  def operation_code
    yield
  rescue OperationError => error
    error.code
  end
end
