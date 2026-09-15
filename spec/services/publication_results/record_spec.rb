require "rails_helper"
require Rails.root.join("lib/kos/push_evidence")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe PublicationResults::Record, :aggregate_failures do
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  let(:now) { Time.current.change(usec: 0) }
  let(:candidate_sha) { "a" * 40 }
  let(:repository) do
    Repository.create!(git_common_dir: "/tmp/#{SecureRandom.uuid}.git", task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Record publication result", task_input_schema_version: "1",
      approved_brief: "Persist the verified publication result before cleanup.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  def prepared_state(canonical: true)
    advance_to_publication(task:, version:, candidate_sha:, now:)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "publisher",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "publication-result-claim", now:)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: "/tmp/worktrees/#{task.number}", state: "confirmed",
      fencing_token: attempt.fencing_token, head_sha: candidate_sha,
      git_common_dir_digest: "sha256:#{'b' * 64}", confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    publication = Publications::Prepare.call(repository:, task_number: task.number, candidate_sha:,
      remote: repository.trusted_remote, base_ref: repository.base_ref, expected_remote_oid: "c" * 40,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now:)
    WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    attempt.reload
    observed_at = (now + 1.second).utc.iso8601(6)
    digest = canonical ? push_digest(publication, attempt, observed_at) : "sha256:#{'f' * 64}"
    Publications::Reconcile.call(repository:, publication_id: publication.id, candidate_sha:,
      observed_remote_tip: "d" * 40, candidate_reachable: true, observed_at:, evidence_digest: digest,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 2.seconds)
    [ publication.reload, attempt, reservation ]
  end

  def push_digest(publication, attempt, observed_at)
    repository_snapshot = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
      "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
      "base_ref" => repository.base_ref }
    publication_snapshot = { "id" => publication.id, "repository_id" => repository.id,
      "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
      "input_context_digest" => attempt.input_context_digest, "candidate_sha" => publication.candidate_sha,
      "remote" => publication.remote, "base_ref" => publication.base_ref,
      "expected_remote_oid" => publication.expected_remote_oid }
    Kos::PushEvidence.digest(repository: repository_snapshot, publication: publication_snapshot,
      candidate_sha:, remote: publication.remote, base_ref: publication.base_ref,
      observed_remote_tip: "d" * 40, candidate_reachable: true, observed_at:)
  end

  def manifest(publication, attempt)
    observed_at = publication.observed_at.utc.iso8601(6)
    { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest, "outcome" => "succeeded", "artifacts" => [
        { "schema_version" => "1", "type" => "publication", "state" => "published",
          "producer" => "workflow-step", "metadata" => { "kind" => "publication",
            "publication_id" => publication.id, "candidate_sha" => candidate_sha,
            "remote" => publication.remote, "base_ref" => publication.base_ref,
            "observed_remote_tip" => publication.observed_remote_tip, "reachable" => true,
            "observed_at" => observed_at } }
      ], "summary" => "Published the reviewed candidate." }
  end

  def record(publication, attempt, result_manifest: manifest(publication, attempt), now: self.now + 3.seconds)
    described_class.call(repository:, publication_id: publication.id, result_manifest:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
  end

  def persistence_summary
    publication, attempt = prepared_state
    submitted = manifest(publication, attempt)
    result = record(publication, attempt, result_manifest: submitted)
    replay = record(publication, attempt, result_manifest: submitted)
    [ result.id == replay.id, result.producing_attempt_id == attempt.id, result.result_manifest == submitted,
      result.approved_review_artifact_id.present?, result.passed_test_artifact_ids.one?, PublicationResult.count ]
  end

  it "preserves the exact successful manifest and idempotently returns the one publication result" do
    expect(persistence_summary).to eq([ true, true, true, true, true, 1 ])
  end

  it "rejects a different replay and keeps the original result immutable" do
    errors = immutable_result_errors
    expect(errors).to eq(%w[invalid_transition immutable no_delete])
  end

  def immutable_result_errors
    publication, attempt = prepared_state
    result = record(publication, attempt)
    changed = manifest(publication, attempt).merge("summary" => "Different")
    replay = operation_error { record(publication, attempt, result_manifest: changed) }
    update = statement_error(/immutable/) { result.update!(recorded_at: now + 10.seconds) }
    destroy = statement_error(/cannot be deleted/) { result.destroy! }
    [ replay, update, destroy ]
  end

  def operation_error
    yield
  rescue OperationError => error
    error.code
  end

  def statement_error(pattern)
    yield
  rescue ActiveRecord::StatementInvalid => error
    pattern.match?(error.message) ? pattern.source.sub("cannot be deleted", "no_delete") : error.message
  end

  it "rejects noncanonical push evidence without recording a result" do
    publication, attempt = prepared_state(canonical: false)

    expect { record(publication, attempt) }
      .to raise_error(OperationError) { |error| expect(error.code).to eq("invalid_artifact") }
    expect(PublicationResult.count).to eq(0)
  end

  it "rejects publication cleanup at the application and database boundaries before recording" do
    expect(cleanup_errors).to eq(%w[invalid_transition database_guard])
  end

  it "does not let a malformed result inserted below the service unlock publication cleanup" do
    expect(malformed_insert_errors).to eq(%w[malformed_result cleanup_guarded])
  end

  it "rejects near-valid bypass manifests with open, invalid-producer, or mismatched-time evidence" do
    expect(near_valid_bypass_errors).to eq(%w[open producer timestamp])
  end

  def malformed_insert_errors
    publication, attempt, reservation = prepared_state
    attributes = bypass_attributes(publication, attempt)
    attributes[:result_manifest] = JSON.generate({ "schema_version" => "1", "outcome" => "succeeded" })
    insert = statement_error(/publication_results_manifest_shape/) { PublicationResult.insert_all!([ attributes ]) }
    release = statement_error(/publication result is required/) { reservation.update!(state: "release_pending") }
    [ insert == "publication_results_manifest_shape" ? "malformed_result" : insert,
      release == "publication result is required" ? "cleanup_guarded" : release ]
  end

  def near_valid_bypass_errors
    publication, attempt, = prepared_state
    variants = { "open" => manifest(publication, attempt).merge("extra" => true),
      "producer" => manifest(publication, attempt).tap { _1["artifacts"][0]["producer"] = "Invalid Producer" },
      "timestamp" => manifest(publication, attempt).tap do |value|
        value["artifacts"][0]["metadata"]["observed_at"] =
          (publication.observed_at + Rational(1, 1_000_000)).iso8601(6)
      end }
    variants.filter_map do |name, value|
      attributes = bypass_attributes(publication, attempt).merge(id: SecureRandom.uuid,
        result_manifest: JSON.generate(value))
      name if insertion_rejected?(attributes)
    end
  end

  def insertion_rejected?(attributes)
    PublicationResult.insert_all!([ attributes ])
    false
  rescue ActiveRecord::StatementInvalid
    true
  end

  def bypass_attributes(publication, attempt)
    review, tests = described_class.send(:validate_candidate_evidence!, task, publication)
    { id: SecureRandom.uuid, repository_id: repository.id, task_id: task.id, publication_id: publication.id,
      producing_attempt_id: attempt.id, input_context_digest: attempt.input_context_digest, candidate_sha:,
      remote: publication.remote, base_ref: publication.base_ref, observed_remote_tip: publication.observed_remote_tip,
      observation_digest: publication.observation_digest, observed_at: publication.observed_at.utc.iso8601(6),
      approved_review_artifact_id: review.id, passed_test_artifact_ids: JSON.generate(tests.map(&:id)),
      result_manifest: JSON.generate(manifest(publication, attempt)), recorded_at: now + 3.seconds,
      created_at: now + 3.seconds, updated_at: now + 3.seconds }
  end

  def cleanup_errors
    _publication, attempt, reservation = prepared_state
    arguments = { repository:, reservation_id: reservation.id, observed_state: "clean", head_sha: candidate_sha,
      evidence_digest: "sha256:#{'e' * 64}", attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 3.seconds }
    application = operation_error { WorktreeReservations::Release.call(**arguments) }
    database = statement_error(/publication result is required/) do
      reservation.update!(state: "release_pending", observed_state: "clean",
        observation_digest: "sha256:#{'e' * 64}")
    end
    [ application, database == "publication result is required" ? "database_guard" : database ]
  end

  it "lets a replacement claim retrieve the original result and finish only worktree cleanup" do
    state = recorded_recovery_state
    spy_on_republication
    expect(recover_before_release_pending(state)).to eq([ true, "release_pending", "released", nil, 1 ])
    expect_no_republication
  end

  def recover_before_release_pending(state)
    publication, attempt, reservation, original = state
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "no_effect",
      evidence_digest: "sha256:#{'e' * 64}", expected_lock_version: task.reload.lock_version,
      now: now + 301.seconds)
    replacement = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "replacement",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "replacement-publication-cleanup", now: now + 302.seconds)
    common = { repository:, reservation_id: reservation.id, evidence_digest: "sha256:#{'e' * 64}",
      attempt_id: replacement.id, fencing_token: replacement.fencing_token,
      expected_lock_version: task.reload.lock_version }
    pending = WorktreeReservations::Release.call(**common, observed_state: "clean", head_sha: candidate_sha,
      now: now + 303.seconds)
    removals = []
    -> { removals << :removed }.call
    released = WorktreeReservations::Release.call(**common, observed_state: "absent", head_sha: nil,
      now: now + 304.seconds)
    [ recovered_result_summary(publication, original), pending.state, released.state,
      task.reload.worktree_reservation_id, removals.length ]
  end

  def recorded_recovery_state(release: false, remove: nil)
    publication, attempt, reservation = prepared_state
    result = record(publication, attempt)
    original = [ result.id, result.result_manifest, result.producing_attempt_id,
      publication.observation_digest, PublicationResult.count ]
    release_clean(reservation, attempt, now + 4.seconds) if release
    remove&.call
    [ publication, attempt, reservation, original ]
  end

  def replacement_for(attempt, observed_state:)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state:,
      evidence_digest: "sha256:#{'e' * 64}", expected_lock_version: task.reload.lock_version,
      now: now + 301.seconds)
    WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "replacement",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "replacement-#{observed_state}", now: now + 302.seconds)
  end

  def release_clean(reservation, attempt, at)
    WorktreeReservations::Release.call(repository:, reservation_id: reservation.id, observed_state: "clean",
      head_sha: candidate_sha, evidence_digest: "sha256:#{'e' * 64}", attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: at)
  end

  def release_absent(reservation, attempt, at)
    WorktreeReservations::Release.call(repository:, reservation_id: reservation.id, observed_state: "absent",
      head_sha: nil, evidence_digest: "sha256:#{'f' * 64}", attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now: at)
  end

  def recovered_result_summary(publication, original)
    retrieved = repository.publication_results.find_by!(publication_id: publication.id)
    [ retrieved.id, retrieved.result_manifest, retrieved.producing_attempt_id,
      publication.reload.observation_digest, PublicationResult.count ] == original
  end

  def spy_on_republication
    allow(Publications::Reconcile).to receive(:call).and_call_original
    allow(Kos::Repository::Push).to receive(:new).and_call_original
    allow(described_class).to receive(:call).and_call_original
  end

  def expect_no_republication
    expect(Publications::Reconcile).not_to have_received(:call)
    expect(Kos::Repository::Push).not_to have_received(:new)
    expect(described_class).not_to have_received(:call)
  end

  it "recovers after release_pending and performs one removal without recreating or reconciling publication" do
    state = recorded_recovery_state(release: true)
    spy_on_republication
    expect(recover_after_pending(state)).to eq([ true, "released", 1 ])
    expect_no_republication
  end

  def recover_after_pending(state)
    publication, attempt, reservation, original = state
    replacement = replacement_for(attempt, observed_state: "worktree_materialized")
    removals = []
    release_clean(reservation, replacement, now + 303.seconds)
    -> { removals << :removed }.call
    released = release_absent(reservation, replacement, now + 304.seconds)
    [ recovered_result_summary(publication, original), released.state, removals.length ]
  end

  it "reconciles absence after physical removal without removing or recreating publication state" do
    removals = []
    state = recorded_recovery_state(release: true, remove: -> { removals << :removed })
    spy_on_republication
    expect(recover_after_physical_removal(state, removals)).to eq([ true, "released", [ :removed ] ])
    expect_no_republication
  end

  def recover_after_physical_removal(state, removals)
    publication, attempt, reservation, original = state
    replacement = replacement_for(attempt, observed_state: "worktree_materialized")
    released = release_absent(reservation, replacement, now + 303.seconds)
    [ recovered_result_summary(publication, original), released.state, removals ]
  end

  it "retrieves the original result after durable release without another cleanup or publication operation" do
    state = durably_released_state
    spy_on_republication
    expect(recover_after_durable_release(state)).to eq([ true, "released", nil, 1 ])
    expect_no_republication
  end

  def durably_released_state
    removals = []
    state = recorded_recovery_state(release: true, remove: -> { removals << :removed })
    _publication, attempt, reservation = state
    release_absent(reservation, attempt, now + 5.seconds)
    [ state, removals ]
  end

  def recover_after_durable_release(state_and_removals)
    state, removals = state_and_removals
    publication, attempt, reservation, original = state
    replacement_for(attempt, observed_state: "no_effect")
    [ recovered_result_summary(publication, original), reservation.reload.state,
      task.reload.worktree_reservation_id, removals.length ]
  end
end
