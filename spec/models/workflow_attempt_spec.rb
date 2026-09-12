require "rails_helper"

RSpec.describe WorkflowAttempt, :aggregate_failures, type: :model do
  def digest
    @digest ||= "sha256:" + ("a" * 64)
  end

  def create_repository(prefix: "R#{SecureRandom.hex(3).upcase}")
    Repository.create!(
      git_common_dir: "/tmp/#{SecureRandom.uuid}.git",
      task_prefix: prefix,
      trusted_remote: "origin",
      trusted_remote_url: "file:///tmp/#{SecureRandom.uuid}.git",
      base_ref: "refs/heads/main"
    )
  end

  def create_workflow
    suffix = SecureRandom.hex(4)
    task_type = TaskType.create!(id: "type-#{suffix}", name: "type-#{suffix}", workflow_id: "workflow-#{suffix}")
    version = WorkflowVersion.create!(
      task_type:,
      workflow_id: task_type.workflow_id,
      version: "1.0.0",
      content_digest: digest
    )
    source = WorkflowState.create!(
      workflow_version: version,
      identifier: "development",
      initial: true,
      execution_mode: "subagent",
      instruction: "Implement the change.",
      worktree_policy: "required",
      repository_changes_policy: "allowed"
    )
    terminal = WorkflowState.create!(workflow_version: version, identifier: "completed", terminal: true)
    version.update!(published_at: Time.current)

    { task_type:, version:, source:, terminal: }
  end

  def create_task(repository: create_repository, workflow: create_workflow, sequence: 1)
    Task.create!(
      repository:,
      sequence:,
      title: "Persist execution state",
      task_type: workflow.fetch(:task_type),
      workflow_version: workflow.fetch(:version),
      workflow_state: workflow.fetch(:source)
    )
  end

  def create_attempt(task:, token: 1, **attributes)
    now = Time.current
    WorkflowAttempt.create!(
      repository: task.repository,
      task:,
      workflow_state: task.workflow_state,
      owner_id: "orchestrator",
      idempotency_key: "attempt-#{SecureRandom.hex(8)}",
      fencing_token: token,
      lease_expires_at: 5.minutes.from_now,
      heartbeat_at: now,
      started_at: now,
      **attributes
    )
  end

  def interrupt(attempt)
    attempt.update!(state: "interrupted", lease_expires_at: nil, completed_at: Time.current,
      reconciliation_state: "no_effect", reconciliation_evidence_digest: digest, reconciled_at: Time.current)
  end

  def finalize(attempt, state: "failed")
    manifest = {
      "schema_version" => "1",
      "attempt_id" => attempt.id,
      "input_context_digest" => digest,
      "outcome" => state,
      "artifacts" => []
    }
    attributes = {
      state:,
      lease_expires_at: nil,
      completed_at: Time.current,
      result_manifest: manifest
    }
    unless attempt.input_context
      attributes[:input_context] = { "schema_version" => "1", "attempt_id" => attempt.id }
      attributes[:input_context_digest] = digest
    end
    attempt.update!(attributes)
  end

  def create_completed_idempotency(repository: nil, command: "task.create", key: "request-key")
    IdempotencyRecord.create!(
      repository:,
      command:,
      idempotency_key: key,
      request_fingerprint: digest,
      state: "completed",
      response_status: 201,
      response_data: { "id" => SecureRandom.uuid },
      completed_at: Time.current
    )
  end

  def create_artifact(attempt, **attributes)
    TaskArtifact.create!(
      repository: attempt.repository,
      task: attempt.task,
      workflow_attempt: attempt,
      artifact_type: "candidate",
      state: "produced",
      producer: "developer",
      metadata: { "kind" => "candidate", "candidate_sha" => "b" * 40 },
      **attributes
    )
  end

  def create_reservation(attempt, path: "/tmp/worktrees/#{SecureRandom.uuid}", **attributes)
    WorktreeReservation.create!(
      repository: attempt.repository,
      task: attempt.task,
      workflow_attempt: attempt,
      branch: "kos/task-#{attempt.task.number}",
      path:,
      fencing_token: attempt.fencing_token,
      **attributes
    )
  end

  def create_repository_effect(attempt, state: "prepared")
    attempt.task.update!(active_attempt: attempt) unless attempt.task.active_attempt_id
    request = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => digest,
      "effect" => { "operation" => "fetch", "remote" => "origin", "ref" => "refs/heads/main" } }
    effect = RepositoryEffect.create!(repository: attempt.repository, task: attempt.task,
      prepared_attempt: attempt, current_owner_attempt: attempt, request_digest: digest,
      request:, prepared_at: Time.current)
    return effect if state == "prepared"

    result = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => attempt.id, "owner_attempt_id" => attempt.id,
      "input_context_digest" => digest, "effect_request_digest" => digest,
      "result" => { "outcome" => state, "operation" => "fetch",
        "error" => { "category" => "transient", "code" => "adapter_unavailable",
          "message" => "Adapter unavailable", "retryable" => true } } }
    effect.update!(state:, result:, reconciled_at: Time.current)
    effect
  end

  def unresolved_completion_error
    attempt = attempt_with_context
    create_repository_effect(attempt)
    attempt.update_columns(state: "failed", lease_expires_at: nil, completed_at: Time.current,
      result_manifest: { "schema_version" => "1", "attempt_id" => attempt.id,
        "input_context_digest" => digest, "outcome" => "failed", "artifacts" => [] }.to_json)
  end

  def invalid_effect_requests
    attempt = attempt_with_context
    incomplete = { "schema_version" => "1", "attempt_id" => attempt.id,
      "input_context_digest" => digest, "effect" => { "operation" => "fetch" } }
    attributes = { repository: attempt.repository, task: attempt.task, prepared_attempt: attempt,
      current_owner_attempt: attempt, request_digest: digest, request: incomplete, prepared_at: Time.current }
    attempt.task.update!(active_attempt: attempt)
    incomplete_error = capture_statement_error { RepositoryEffect.create!(attributes) }
    attempt.task.update!(active_attempt: nil)
    valid = incomplete.deep_dup
    valid.fetch("effect").merge!("remote" => "origin", "ref" => "refs/heads/main")
    inactive_error = capture_statement_error { RepositoryEffect.create!(attributes.merge(request: valid)) }
    [ incomplete_error, inactive_error ]
  end

  def mismatched_result_owner_error
    attempt = attempt_with_context
    effect = create_repository_effect(attempt)
    result = { "schema_version" => "1", "effect_intent_id" => effect.id,
      "request_attempt_id" => attempt.id, "owner_attempt_id" => SecureRandom.uuid,
      "input_context_digest" => digest, "effect_request_digest" => digest,
      "result" => { "outcome" => "unknown", "operation" => "fetch",
        "error" => { "category" => "transient", "code" => "adapter_unavailable",
          "message" => "Adapter unavailable", "retryable" => true } } }
    capture_statement_error do
      effect.update_columns(state: "unknown", result: result.to_json, reconciled_at: Time.current)
    end
  end

  def capture_statement_error
    yield
    nil
  rescue ActiveRecord::StatementInvalid => error
    error.message
  end

  def attempt_with_context
    attempt = create_attempt(task: create_task)
    attempt.update!(input_context: { "schema_version" => "1" }, input_context_digest: digest)
    attempt
  end

  def cross_repository_attempt
    task = create_task
    attributes = create_attempt(task:).attributes.except("id", "repository_id", "created_at", "updated_at")
    described_class.new(attributes.merge(repository_id: create_repository.id, idempotency_key: "different-key"))
  end

  def incomplete_idempotency_record
    IdempotencyRecord.new(
      command: "effect.prepare",
      idempotency_key: "effect-request",
      request_fingerprint: digest
    )
  end

  def completed_idempotency_without_status
    IdempotencyRecord.new(
      command: "task.create",
      idempotency_key: "missing-status",
      request_fingerprint: digest,
      state: "completed",
      response_data: { "id" => SecureRandom.uuid },
      completed_at: Time.current
    )
  end

  def cross_owned_artifact
    attempt = create_attempt(task: create_task)
    other_task = create_task
    TaskArtifact.new(
      repository: other_task.repository,
      task: other_task,
      workflow_attempt: attempt,
      artifact_type: "document",
      state: "produced",
      producer: "planner",
      metadata: { "kind" => "document" }
    )
  end

  def seed_idempotency_scopes
    first_repository = create_repository
    create_completed_idempotency(key: "shared-key")
    create_completed_idempotency(repository: first_repository, key: "shared-key")
    create_completed_idempotency(repository: create_repository, key: "shared-key")
    create_completed_idempotency(command: "workflow.publish", key: "shared-key")
    first_repository
  end

  def release(reservation)
    reservation.update!(
      state: "confirmed",
      git_common_dir_digest: digest,
      head_sha: "b" * 40,
      confirmed_at: Time.current
    )
    reservation.update!(
      state: "released",
      observed_state: "absent",
      observation_digest: digest,
      released_at: Time.current
    )
  end

  def transferable_reservation
    task = create_task
    first = create_attempt(task:)
    reservation = create_reservation(first)
    interrupt(first)
    [ reservation, create_attempt(task:, token: 2) ]
  end

  def attempts_with_tied_timestamps(task)
    timestamp = Time.current
    first = create_attempt(task:, started_at: timestamp, heartbeat_at: timestamp)
    finalize(first, state: "needs_human")
    second = create_attempt(task:, token: 2, started_at: timestamp, heartbeat_at: timestamp)
    finalize(second)
  end

  def task_with_cancelled_terminal
    task_type = TaskType.create!(id: "cancel-type", name: "cancel-type", workflow_id: "cancel-workflow")
    version = WorkflowVersion.create!(task_type:, workflow_id: task_type.workflow_id, version: "1.0.0",
      content_digest: digest)
    source = WorkflowState.create!(workflow_version: version, identifier: "development", initial: true,
      execution_mode: "subagent", instruction: "Work.", worktree_policy: "required",
      repository_changes_policy: "allowed")
    terminal = WorkflowState.create!(workflow_version: version, identifier: "cancelled", terminal: true)
    version.update!(published_at: Time.current)
    task = create_task(workflow: { task_type:, version:, source: })
    task.update!(workflow_state: terminal)
    task
  end

  it "persists attempt associations and JSON documents" do
    attempt = attempt_with_context

    expect(attempt.reload.input_context).to eq("schema_version" => "1")
    expect(attempt.task.workflow_attempts).to contain_exactly(attempt)
  end

  it "allows only one unreconciled started attempt per task" do
    task = create_task
    create_attempt(task:)

    expect { create_attempt(task:, token: 2) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "requires consecutive fencing tokens" do
    task = create_task
    first = create_attempt(task:)
    interrupt(first)

    expect { create_attempt(task:, token: 3) }
      .to raise_error(ActiveRecord::StatementInvalid, /next task token/)
  end

  it "retains attempt history so fencing tokens cannot be reused" do
    attempt = create_attempt(task: create_task)

    expect { attempt.delete }.to raise_error(ActiveRecord::StatementInvalid, /attempt cannot be deleted/)
  end

  it "binds an attempt to the task repository and current workflow state" do
    expect { cross_repository_attempt.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /current task state/)
  end

  it "rejects an attempt for a terminal workflow state" do
    task = create_task
    task.update!(workflow_state: task.workflow_version.workflow_states.find_by!(terminal: true))

    expect { create_attempt(task:) }.to raise_error(ActiveRecord::StatementInvalid, /current task state/)
  end

  it "requires a result manifest for a terminal attempt" do
    attempt = create_attempt(task: create_task)

    expect {
      attempt.update_columns(state: "failed", lease_expires_at: nil, completed_at: Time.current)
    }.to raise_error(ActiveRecord::StatementInvalid, /workflow_attempts_lifecycle_shape/)
  end

  it "persists a result manifest matching the terminal attempt" do
    attempt = create_attempt(task: create_task)
    finalize(attempt)

    expect(attempt.reload.result_manifest.fetch("outcome")).to eq("failed")
  end

  it "retains the final heartbeat on a terminal attempt" do
    attempt = create_attempt(task: create_task)

    expect { attempt.update_columns(state: "interrupted", heartbeat_at: nil, lease_expires_at: nil,
      completed_at: Time.current) }.to raise_error(ActiveRecord::StatementInvalid, /timestamp_order/)
  end

  it "freezes finalized context" do
    attempt = attempt_with_context

    expect { attempt.update!(input_context: { "version" => 2 }) }
      .to raise_error(ActiveRecord::StatementInvalid, /context is immutable/)
  end

  it "freezes terminal attempts" do
    attempt = create_attempt(task: create_task)
    finalize(attempt)

    expect { attempt.touch }.to raise_error(ActiveRecord::StatementInvalid, /terminal attempt is immutable/)
  end

  it "requires complete reconciliation evidence on an interrupted attempt" do
    attempt = create_attempt(task: create_task)

    expect {
      attempt.update_columns(state: "interrupted", lease_expires_at: nil, completed_at: Time.current,
        reconciliation_state: "no_effect")
    }.to raise_error(ActiveRecord::StatementInvalid, /workflow_attempts_reconciliation_shape/)
  end

  it "rejects reconciliation evidence on a non-interrupted attempt" do
    attempt = create_attempt(task: create_task)

    expect {
      attempt.update_columns(reconciliation_state: "no_effect", reconciliation_evidence_digest: digest,
        reconciled_at: Time.current)
    }.to raise_error(ActiveRecord::StatementInvalid, /workflow_attempts_reconciliation_shape/)
  end

  it "keeps attached reconciliation evidence immutable" do
    attempt = create_attempt(task: create_task)
    attempt.update!(state: "interrupted", lease_expires_at: nil, completed_at: Time.current,
      reconciliation_state: "no_effect", reconciliation_evidence_digest: digest, reconciled_at: Time.current)

    expect { attempt.update_column(:reconciliation_state, "publication_unknown") }
      .to raise_error(ActiveRecord::StatementInvalid, /terminal attempt is immutable/)
  end

  it "isolates global idempotency scope by command" do
    seed_idempotency_scopes

    expect { create_completed_idempotency(key: "shared-key") }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "isolates repository idempotency scopes" do
    first_repository = seed_idempotency_scopes

    expect { create_completed_idempotency(repository: first_repository, key: "shared-key") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "round-trips completed idempotency data and protects retained records" do
    record = create_completed_idempotency

    expect(record.reload.response_data).to include("id")
    expect { record.update_column(:response_status, 200) }
      .to raise_error(ActiveRecord::StatementInvalid, /completed idempotency record is immutable/)
    expect { record.delete }.to raise_error(ActiveRecord::StatementInvalid, /record cannot be deleted/)
  end

  it "requires an in-progress idempotency record to name its durable intent" do
    expect { incomplete_idempotency_record.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /idempotency_records_lifecycle_shape/)
  end

  it "requires a completed idempotency record to retain its HTTP status" do
    expect { completed_idempotency_without_status.save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /idempotency_records_lifecycle_shape/)
  end

  it "persists artifacts with matching ownership and metadata" do
    attempt = create_attempt(task: create_task)
    artifact = create_artifact(attempt)

    expect(artifact.reload.metadata.fetch("kind")).to eq("candidate")
    expect(artifact.task).to eq(attempt.task)
  end

  it "protects artifacts from mutation and deletion" do
    artifact = create_artifact(create_attempt(task: create_task))

    expect { artifact.update_column(:state, "failed") }
      .to raise_error(ActiveRecord::StatementInvalid, /task artifact is immutable/)
    expect { artifact.delete }.to raise_error(ActiveRecord::StatementInvalid, /artifact cannot be deleted/)
  end

  it "rejects invalid artifact type-state and metadata combinations in SQLite" do
    attempt = create_attempt(task: create_task)

    expect { create_artifact(attempt, state: "approved").save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /task_artifacts_type_state_pair/)
    expect { create_artifact(attempt, metadata: { "kind" => "test" }).save!(validate: false) }
      .to raise_error(ActiveRecord::StatementInvalid, /task_artifacts_metadata_kind/)
  end

  it "binds test state to its exit code" do
    attempt = create_attempt(task: create_task)

    expect { create_artifact(attempt, artifact_type: "test", state: "passed",
      metadata: { "kind" => "test", "exit_code" => 1 }) }
      .to raise_error(ActiveRecord::StatementInvalid, /test_result_binding/)
  end

  it "requires test metadata to include an integer exit code" do
    attempt = create_attempt(task: create_task)

    expect { create_artifact(attempt, artifact_type: "test", state: "passed",
      metadata: { "kind" => "test" }) }
      .to raise_error(ActiveRecord::StatementInvalid, /test_result_binding/)
  end

  it "binds review state to its verdict" do
    attempt = create_attempt(task: create_task)

    expect { create_artifact(attempt, artifact_type: "review", state: "approved",
      metadata: { "kind" => "review", "verdict" => "changes_requested" }) }
      .to raise_error(ActiveRecord::StatementInvalid, /review_verdict_binding/)
  end

  it "requires publication reachability to be a JSON boolean" do
    attempt = create_attempt(task: create_task)

    expect { create_artifact(attempt, artifact_type: "publication", state: "published",
      metadata: { "kind" => "publication", "reachable" => 1 }) }
      .to raise_error(ActiveRecord::StatementInvalid, /publication_reachability/)
  end

  it "rejects an artifact owned by another task or repository" do
    expect { cross_owned_artifact.save!(validate: false) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "enforces one active reservation per task" do
    task = create_task
    attempt = create_attempt(task:)
    create_reservation(attempt)

    expect { create_reservation(attempt, path: "/tmp/worktrees/other") }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "enforces installation-global active worktree paths" do
    path = "/tmp/worktrees/shared"
    create_reservation(create_attempt(task: create_task), path:)
    other_attempt = create_attempt(task: create_task)

    expect { create_reservation(other_attempt, path:) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "releases reservation keys" do
    attempt = create_attempt(task: create_task)
    reservation = create_reservation(attempt)
    release(reservation)

    expect { create_reservation(attempt, path: reservation.path) }.not_to raise_error
  end

  it "retains released reservation history" do
    reservation = create_reservation(create_attempt(task: create_task))

    expect { reservation.delete }
      .to raise_error(ActiveRecord::StatementInvalid, /reservation cannot be deleted/)
  end

  it "transfers reservation ownership to a matching later attempt" do
    reservation, second = transferable_reservation

    expect { reservation.update!(workflow_attempt: second, fencing_token: second.fencing_token) }
      .to change(reservation, :workflow_attempt).to(second)
  end

  it "protects repository effect intent identity and retained history" do
    effect = create_repository_effect(attempt_with_context)

    expect { effect.update_column(:request_digest, "sha256:#{'b' * 64}") }
      .to raise_error(ActiveRecord::StatementInvalid, /intent is immutable/)
    expect { effect.delete }
      .to raise_error(ActiveRecord::StatementInvalid, /effect cannot be deleted/)
  end

  it "keeps terminal repository effects immutable" do
    effect = create_repository_effect(attempt_with_context, state: "failed")

    expect { effect.touch }
      .to raise_error(ActiveRecord::StatementInvalid, /terminal repository effect is immutable/)
  end

  it "enforces unresolved effect completion guards in SQLite" do
    expect { unresolved_completion_error }
      .to raise_error(ActiveRecord::StatementInvalid, /unresolved repository effect/)
  end

  it "rejects incomplete effect requests and owners that are not the active attempt" do
    expect(invalid_effect_requests)
      .to contain_exactly(include("request_shape"), include("preparing active attempt"))
  end

  it "binds persisted result ownership in SQLite" do
    expect(mismatched_result_owner_error).to include("result_binding")
  end

  it "rejects reservation ownership from another task" do
    reservation, = transferable_reservation
    other_attempt = create_attempt(task: create_task)

    expect { reservation.update!(workflow_attempt: other_attempt, fencing_token: other_attempt.fencing_token) }
      .to raise_error(ActiveRecord::StatementInvalid, /owner must be an active attempt/)
  end

  it "accepts task execution pointers owned by that task" do
    task = create_task
    attempt = create_attempt(task:)
    reservation = create_reservation(attempt)

    expect { task.update!(active_attempt: attempt, worktree_reservation: reservation) }.not_to raise_error
  end

  it "derives blocked state from the latest fencing token instead of attempt timestamps" do
    task = create_task
    attempts_with_tied_timestamps(task)

    expect(task.status).to eq("open")
  end

  it "derives cancelled state from a non-completed terminal workflow state" do
    expect(task_with_cancelled_terminal.status).to eq("cancelled")
  end

  it "requires clearing the task pointer before completing its attempt" do
    task = create_task
    attempt = create_attempt(task:)
    task.update!(active_attempt: attempt)

    expect { finalize(attempt) }.to raise_error(ActiveRecord::StatementInvalid, /release its active attempt/)
  end

  it "requires an active attempt to match the task workflow state" do
    task = create_task
    task.update!(active_attempt: create_attempt(task:))
    terminal = task.workflow_version.workflow_states.find_by!(terminal: true)

    expect { task.update!(workflow_state: terminal) }.to raise_error(ActiveRecord::StatementInvalid, /must match/)
  end

  it "rejects assigning an attempt from an earlier workflow state" do
    task = create_task
    attempt = create_attempt(task:)
    task.update!(workflow_state: task.workflow_version.workflow_states.find_by!(terminal: true))

    expect { task.update!(active_attempt: attempt) }.to raise_error(ActiveRecord::StatementInvalid, /must be started/)
  end

  it "requires clearing the task pointer before releasing its reservation" do
    task = create_task
    reservation = create_reservation(create_attempt(task:))
    task.update!(worktree_reservation: reservation)

    expect { release(reservation) }.to raise_error(ActiveRecord::StatementInvalid, /pointer first/)
  end

  it "rejects a task execution pointer owned by another task" do
    attempt = create_attempt(task: create_task)
    other_task = create_task

    expect { other_task.update!(active_attempt: attempt) }
      .to raise_error(ActiveRecord::StatementInvalid, /active attempt must be started for this task/)
  end
end
