require "rails_helper"
require "tmpdir"
require Rails.root.join("spec/support/git_repository_helpers")
require Rails.root.join("spec/support/publication_preflight_helpers")
require Rails.root.join("spec/support/workflow_catalog_helpers")

RSpec.describe WorkflowSteps::Complete, :aggregate_failures do
  include GitRepositoryHelpers
  include PublicationPreflightHelpers
  include WorkflowCatalogHelpers

  let(:git_path) { Dir.mktmpdir("kos-base-synchronization") }
  let(:repository) do
    Repository.create!(git_common_dir: File.join(git_path, ".git"), task_prefix: "KOS",
      trusted_remote: "origin", trusted_remote_url: "file:///tmp/remote.git", base_ref: "refs/heads/main")
  end
  let(:version) { publish_workflow(JSON.parse(File.read(Rails.root.join("workflows/quick-fix/1.0.2.json")))) }
  let(:task) do
    Task.create!(repository:, sequence: 1, title: "Synchronize moved base", task_input_schema_version: "1",
      approved_brief: "Synchronize the candidate and rerun its checks.", task_type: quick_fix_task_type,
      workflow_version: version, workflow_state: version.workflow_states.find_by!(initial: true))
  end

  after { FileUtils.remove_entry(git_path) if File.exist?(git_path) }

  def now = Time.current.change(usec: 0)
  def digest = "sha256:#{'a' * 64}"

  def artifact(type, state, metadata)
    { "schema_version" => "1", "type" => type, "state" => state,
      "producer" => "workflow-step", "metadata" => metadata }
  end

  def prepare_attempt
    old_sha = initialize_git_repository(git_path, task_number: task.number, files: { "change.txt" => "old\n" })
    File.binwrite(File.join(git_path, "change.txt"), "rebased\n")
    git(git_path, "add", "change.txt")
    git(git_path, "commit", "-m", "Rebased candidate", "-m", "KOS-Task: #{task.number}")
    new_sha = git(git_path, "rev-parse", "HEAD").strip

    development = version.workflow_states.find_by!(identifier: "development")
    review = version.workflow_states.find_by!(identifier: "review")
    synchronization = version.workflow_states.find_by!(identifier: "base-synchronization")
    task.update!(workflow_state: development)
    candidate_attempt = complete_attempt(task:, state: development, target: review, token: 1, now:)
    TaskArtifact.create!(repository:, task:, workflow_attempt: candidate_attempt, artifact_type: "candidate",
      state: "produced", producer: "workflow-step", metadata: { "kind" => "candidate",
        "candidate_sha" => old_sha, "task_trailer" => task.number })
    task.update!(workflow_state: synchronization)
    attempt = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "synchronizer",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "base-synchronization-claim", now:)
    reservation = WorktreeReservation.create!(repository:, task:, workflow_attempt: attempt,
      branch: "kos/task-#{task.number}", path: git_path, state: "confirmed", fencing_token: attempt.fencing_token,
      head_sha: old_sha, git_common_dir_digest: "sha256:#{'b' * 64}", confirmed_at: now)
    task.reload.update!(worktree_reservation: reservation)
    context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, now:)
    Publication.create!(repository:, task:, prepared_attempt: attempt, current_owner_attempt: attempt,
      observation_owner_attempt: attempt,
      candidate_sha: old_sha, remote: repository.trusted_remote, base_ref: repository.base_ref,
      expected_remote_oid: "d" * 40, state: "superseded", observed_remote_tip: "c" * 40,
      candidate_reachable: false, observation_digest: digest, observed_at: now, prepared_at: now, reconciled_at: now)
    [ attempt.reload, reservation, context, old_sha, new_sha ]
  end

  def reconcile_effect(attempt, request, result, prepared_at)
    effect = RepositoryEffects::Prepare.call(repository:, task_number: task.number, effect_request: request,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: prepared_at)
    envelope = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => effect.prepared_attempt_id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest, "effect_request_digest" => effect.request_digest,
      "result" => result }
    RepositoryEffects::Reconcile.call(repository:, effect_id: effect.id, effect_result: envelope,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: prepared_at)
  end

  def successful_effects(attempt, reservation, context, new_sha)
    fetch, rebase = prepare_rebase(attempt, reservation, context)
    RepositoryEffects::ReconcileRebase.call(repository:, effect_id: rebase.id, head_sha: new_sha,
      rebase_evidence_digest: rebase_digest(attempt, reservation, rebase, new_sha),
      worktree_evidence_digest: observation_digest(attempt, reservation, new_sha),
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: now + 3.seconds)
    [ fetch, rebase ]
  end

  def prepare_rebase(attempt, reservation, context, started_at: now)
    fetch_request = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest,
      "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
    fetch = reconcile_effect(attempt, fetch_request, { "outcome" => "succeeded", "operation" => "fetch",
      "remote" => "origin", "ref" => "refs/heads/main", "observed_oid" => "c" * 40,
      "evidence_digest" => digest }, started_at + 1.second)
    rebase_request = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest,
      "effect" => { "operation" => "rebase", "reservation_id" => reservation.id,
        "expected_head_sha" => context.dig("worktree", "head_sha"), "onto_sha" => "c" * 40 } }
    rebase = RepositoryEffects::Prepare.call(repository:, task_number: task.number, effect_request: rebase_request,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version, now: started_at + 2.seconds)
    [ fetch, rebase ]
  end

  def observation_digest(attempt, reservation, head_sha)
    Kos::WorktreeObservation.digest(repository_id: repository.id,
      reservation_id: reservation.id, fencing_token: attempt.fencing_token, path: reservation.path,
      branch: reservation.branch, state: "clean", head_sha:,
      git_common_dir_digest: reservation.git_common_dir_digest,
      input_context_digest: attempt.input_context_digest)
  end

  def rebase_digest(attempt, reservation, rebase, head_sha, original_base_sha: "d" * 40)
    fetch = attempt.owned_repository_effects.find { _1.request.dig("effect", "operation") == "fetch" }
    repository_data = { "id" => repository.id, "git_common_dir" => repository.git_common_dir,
      "trusted_remote" => repository.trusted_remote, "trusted_remote_url" => repository.trusted_remote_url,
      "base_ref" => repository.base_ref }
    snapshot = ->(effect) do
      { "id" => effect.id, "repository_id" => repository.id, "current_owner_attempt_id" => attempt.id,
        "fencing_token" => attempt.fencing_token, "request_digest" => effect.request_digest,
        "request" => effect.request }
    end
    fetch_result = { "schema_version" => "1", "repository_id" => repository.id, "effect_id" => fetch.id,
      "current_owner_attempt_id" => attempt.id, "fencing_token" => attempt.fencing_token,
      "effect_request_digest" => fetch.request_digest }.merge(fetch.result.fetch("result"))
    Kos::RebaseEvidence.digest(repository: repository_data,
      reservation: reservation.attributes.slice("id", "repository_id", "state", "path", "branch", "fencing_token"),
      effect: snapshot.call(rebase), fetch: { "request" => { "schema_version" => "1", "operation" => "fetch",
        "repository" => repository_data, "effect" => snapshot.call(fetch) }, "result" => fetch_result },
      original_base_sha:, expected_head_sha: reservation.head_sha,
      onto_sha: rebase.request.dig("effect", "onto_sha"), head_sha:)
  end

  def complete_synchronization(attempt, candidate_sha, completed_at: now + 4.seconds)
    artifacts = [ artifact("candidate", "produced", { "kind" => "candidate", "candidate_sha" => candidate_sha,
      "task_trailer" => task.number }), artifact("test", "passed", { "kind" => "test",
      "candidate_sha" => candidate_sha, "command" => "mise run check", "exit_code" => 0,
      "log_digest" => digest }) ]
    manifest = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest, "outcome" => "succeeded", "artifacts" => artifacts }
    described_class.call(repository:, task_number: task.number, to_status: "review", attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version, manifest:,
      now: completed_at)
  end

  it "registers only the synchronized checked candidate and returns to review" do
    summary = successful_synchronization_summary
    expect(summary).to eq([ "review", summary.fetch(1), "clean", "succeeded", summary.fetch(1), false ])
  end

  def successful_synchronization_summary
    attempt, reservation, context, old_sha, new_sha = prepare_attempt
    successful_effects(attempt, reservation, context, new_sha)
    result = complete_synchronization(attempt, new_sha)
    [ result.task.workflow_state.identifier, reservation.reload.head_sha, reservation.observed_state,
      attempt.reload.state, WorkflowSteps::CurrentCandidate.call(task.reload).metadata.fetch("candidate_sha"),
      old_sha == new_sha ]
  end

  it "rejects reuse of the superseded candidate after successful effects" do
    expect(superseded_candidate_summary).to eq([ "invalid_artifact", "base-synchronization", "started" ])
  end

  def superseded_candidate_summary
    attempt, reservation, context, old_sha, new_sha = prepare_attempt
    successful_effects(attempt, reservation, context, new_sha)
    complete_synchronization(attempt, old_sha)
  rescue OperationError => error
    [ error.code, task.reload.workflow_state.identifier, attempt.reload.state ]
  end

  it "rejects an untrusted fetch and a rebase before its one successful fetch" do
    expect(invalid_sequence_summary).to eq([ %w[invalid_transition invalid_transition], 0 ])
  end

  def invalid_sequence_summary
    attempt, reservation, context, = prepare_attempt
    untrusted = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest,
      "effect" => { "operation" => "fetch", "remote" => "upstream", "ref" => "refs/heads/main" } }
    premature = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest,
      "effect" => { "operation" => "rebase", "reservation_id" => reservation.id,
        "expected_head_sha" => context.dig("worktree", "head_sha"), "onto_sha" => "c" * 40 } }

    codes = [ untrusted, premature ].map do |request|
      RepositoryEffects::Prepare.call(repository:, task_number: task.number, effect_request: request,
        attempt_id: attempt.id, fencing_token: attempt.fencing_token,
        expected_lock_version: task.reload.lock_version, now: now + 1.second)
    rescue OperationError => error
      error.code
    end
    [ codes, attempt.owned_repository_effects.count ]
  end

  it "rolls back both records when the clean observation is not canonical" do
    expect(noncanonical_reconciliation_summary).to eq([ "invalid_transition", "prepared", nil, true ])
  end

  def noncanonical_reconciliation_summary
    attempt, reservation, context, old_sha, new_sha = prepare_attempt
    _fetch, rebase = prepare_rebase(attempt, reservation, context)
    RepositoryEffects::ReconcileRebase.call(repository:, effect_id: rebase.id, head_sha: new_sha,
      rebase_evidence_digest: rebase_digest(attempt, reservation, rebase, new_sha),
      worktree_evidence_digest: "sha256:#{'f' * 64}", attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
  rescue OperationError => error
    [ error.code, rebase.reload.state, reservation.reload.observed_state, reservation.head_sha == old_sha ]
  end

  it "rejects the non-atomic version 1 success path for synchronization rebase" do
    expect(generic_rebase_reconciliation_summary).to eq([ "invalid_transition", "prepared" ])
  end

  def generic_rebase_reconciliation_summary
    attempt, reservation, context, _old_sha, new_sha = prepare_attempt
    _fetch, rebase = prepare_rebase(attempt, reservation, context)
    result = { "schema_version" => "1", "effect_intent_id" => rebase.id,
      "request_attempt_id" => attempt.id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => attempt.input_context_digest, "effect_request_digest" => rebase.request_digest,
      "result" => { "outcome" => "succeeded", "operation" => "rebase", "head_sha" => new_sha,
        "evidence_digest" => digest } }
    RepositoryEffects::Reconcile.call(repository:, effect_id: rebase.id, effect_result: result,
      attempt_id: attempt.id, fencing_token: attempt.fencing_token,
      expected_lock_version: task.reload.lock_version)
  rescue OperationError => error
    [ error.code, rebase.reload.state ]
  end


  it "rejects rebase evidence that does not match the durable intent and fetch" do
    expect(invalid_rebase_evidence_code).to eq("invalid_transition")
  end

  def invalid_rebase_evidence_code
    attempt, reservation, context, _old_sha, new_sha = prepare_attempt
    _fetch, rebase = prepare_rebase(attempt, reservation, context)
    RepositoryEffects::ReconcileRebase.call(repository:, effect_id: rebase.id, head_sha: new_sha,
      rebase_evidence_digest: digest,
      worktree_evidence_digest: observation_digest(attempt, reservation, new_sha), attempt_id: attempt.id,
      fencing_token: attempt.fencing_token, expected_lock_version: task.reload.lock_version)
  rescue OperationError => error
    error.code
  end

  it "reconciles a replacement owner's verified no-op rebase after interruption" do
    summary = interrupted_rebase_adoption_summary
    expect(summary).to eq([ "review", 2, 4, true ])
  end

  it "finds the latest durable rebase across an additional empty interrupted attempt" do
    expect(interrupted_rebase_adoption_summary(extra_interruption: true)).to eq([ "review", 2, 4, true ])
  end

  def interrupted_rebase_adoption_summary(extra_interruption: false)
    attempt, reservation, context, _old_sha, new_sha = prepare_attempt
    successful_effects(attempt, reservation, context, new_sha)
    WorkflowAttempts::Reconcile.call(repository:, attempt_id: attempt.id, observed_state: "no_effect",
      evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: now + 301.seconds)
    replacement = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "replacement",
      lease_seconds: 300, expected_lock_version: task.reload.lock_version,
      idempotency_key: "replacement-synchronization", now: now + 302.seconds)
    if extra_interruption
      WorkflowAttempts::Reconcile.call(repository:, attempt_id: replacement.id, observed_state: "no_effect",
        evidence_digest: digest, expected_lock_version: task.reload.lock_version, now: now + 603.seconds)
      replacement = WorkflowAttempts::Claim.call(repository:, task_number: task.number, owner_id: "second-replacement",
        lease_seconds: 300, expected_lock_version: task.reload.lock_version,
        idempotency_key: "second-replacement-synchronization", now: now + 604.seconds)
    end
    replacement_started_at = extra_interruption ? now + 604.seconds : now + 302.seconds
    replacement_context = WorkflowSteps::CaptureContext.call(repository:, attempt_id: replacement.id,
      fencing_token: replacement.fencing_token, expected_lock_version: task.reload.lock_version,
      now: replacement_started_at)
    replacement.reload
    _fetch, rebase = prepare_rebase(replacement, reservation.reload, replacement_context,
      started_at: replacement_started_at)
    RepositoryEffects::ReconcileRebase.call(repository:, effect_id: rebase.id, head_sha: new_sha,
      rebase_evidence_digest: rebase_digest(replacement, reservation.reload, rebase, new_sha,
        original_base_sha: "c" * 40),
      worktree_evidence_digest: observation_digest(replacement, reservation.reload, new_sha),
      attempt_id: replacement.id, fencing_token: replacement.fencing_token,
      expected_lock_version: task.reload.lock_version, now: replacement_started_at + 3.seconds)
    result = complete_synchronization(replacement, new_sha, completed_at: replacement_started_at + 4.seconds)
    [ result.task.workflow_state.identifier, replacement.owned_repository_effects.count,
      RepositoryEffect.where(task:).count, replacement_context.dig("worktree", "head_sha") == new_sha ]
  end
end
