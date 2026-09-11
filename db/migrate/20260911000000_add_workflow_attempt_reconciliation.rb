class AddWorkflowAttemptReconciliation < ActiveRecord::Migration[8.1]
  def up
    drop_attempt_triggers
    add_column :workflow_attempts, :reconciliation_state, :string
    add_column :workflow_attempts, :reconciliation_evidence_digest, :string
    add_column :workflow_attempts, :reconciled_at, :datetime
    add_column :workflow_attempts, :legacy_reconciliation_pending, :boolean, null: false, default: false
    execute "UPDATE workflow_attempts SET legacy_reconciliation_pending = 1 WHERE state = 'interrupted'"

    add_check_constraint :workflow_attempts, <<~SQL.squish, name: "workflow_attempts_reconciliation_state_values"
      reconciliation_state IS NULL OR reconciliation_state IN (
        'no_effect', 'worktree_materialized', 'repository_effect_pending', 'publication_unknown'
      )
    SQL
    add_check_constraint :workflow_attempts, <<~SQL.squish, name: "workflow_attempts_reconciliation_evidence_digest_format"
      reconciliation_evidence_digest IS NULL OR (
        substr(reconciliation_evidence_digest, 1, 7) = 'sha256:'
        AND length(reconciliation_evidence_digest) = 71
        AND substr(reconciliation_evidence_digest, 8) NOT GLOB '*[^0-9a-f]*'
      )
    SQL
    add_check_constraint :workflow_attempts, <<~SQL.squish, name: "workflow_attempts_reconciliation_shape"
      (reconciliation_state IS NULL AND reconciliation_evidence_digest IS NULL AND reconciled_at IS NULL
        AND (state <> 'interrupted' OR legacy_reconciliation_pending = 1))
      OR (state = 'interrupted' AND reconciliation_state IS NOT NULL
        AND reconciliation_evidence_digest IS NOT NULL AND reconciled_at IS NOT NULL
        AND legacy_reconciliation_pending = 0)
    SQL
    add_check_constraint :workflow_attempts, "legacy_reconciliation_pending IN (0, 1)",
      name: "workflow_attempts_legacy_reconciliation_pending_boolean"

    restore_attempt_triggers(allow_reconciliation_attachment: true)
  end

  def down
    drop_attempt_triggers
    remove_check_constraint :workflow_attempts, name: "workflow_attempts_legacy_reconciliation_pending_boolean"
    remove_check_constraint :workflow_attempts, name: "workflow_attempts_reconciliation_shape"
    remove_check_constraint :workflow_attempts, name: "workflow_attempts_reconciliation_evidence_digest_format"
    remove_check_constraint :workflow_attempts, name: "workflow_attempts_reconciliation_state_values"
    remove_column :workflow_attempts, :reconciled_at
    remove_column :workflow_attempts, :reconciliation_evidence_digest
    remove_column :workflow_attempts, :reconciliation_state
    remove_column :workflow_attempts, :legacy_reconciliation_pending
    restore_attempt_triggers(allow_reconciliation_attachment: false)
  end

  private

  def drop_attempt_triggers
    %w[
      workflow_attempts_primary_key_immutable
      workflow_attempts_current_task_state
      workflow_attempts_monotonic_fencing
      workflow_attempts_immutable_identity
      workflow_attempts_frozen_context
      workflow_attempts_terminal_immutable
      workflow_attempts_terminal_requires_detached_task
      workflow_attempts_no_delete
      workflow_attempts_legacy_reconciliation_pending_insert
      workflow_attempts_legacy_reconciliation_pending_update
    ].each { |name| execute "DROP TRIGGER IF EXISTS #{name}" }
  end

  def restore_attempt_triggers(allow_reconciliation_attachment:)
    restore_reconciliation_pending_triggers if allow_reconciliation_attachment
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_primary_key_immutable
      BEFORE UPDATE OF id ON workflow_attempts
      BEGIN
        SELECT RAISE(ABORT, 'primary key is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_current_task_state
      BEFORE INSERT ON workflow_attempts
      WHEN NOT EXISTS (
        SELECT 1 FROM tasks
        JOIN workflow_states ON workflow_states.id = tasks.workflow_state_id
        WHERE tasks.id = NEW.task_id
          AND tasks.repository_id = NEW.repository_id
          AND tasks.workflow_state_id = NEW.workflow_state_id
          AND workflow_states.terminal = 0
      )
      BEGIN
        SELECT RAISE(ABORT, 'attempt state must be the current task state');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_monotonic_fencing
      BEFORE INSERT ON workflow_attempts
      WHEN NEW.fencing_token <> COALESCE((
        SELECT MAX(fencing_token) + 1 FROM workflow_attempts
        WHERE task_id = NEW.task_id AND repository_id = NEW.repository_id
      ), 1)
      BEGIN
        SELECT RAISE(ABORT, 'attempt fencing token must be the next task token');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_immutable_identity
      BEFORE UPDATE OF repository_id, task_id, workflow_state_id, owner_id, idempotency_key,
        fencing_token, started_at ON workflow_attempts
      BEGIN
        SELECT RAISE(ABORT, 'attempt identity is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_frozen_context
      BEFORE UPDATE OF input_context, input_context_digest ON workflow_attempts
      WHEN OLD.input_context IS NOT NULL
        AND (NEW.input_context IS NOT OLD.input_context OR NEW.input_context_digest IS NOT OLD.input_context_digest)
      BEGIN
        SELECT RAISE(ABORT, 'attempt context is immutable after finalization');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_terminal_immutable
      BEFORE UPDATE ON workflow_attempts
      WHEN OLD.state <> 'started'#{reconciliation_attachment_exception(allow_reconciliation_attachment)}
      BEGIN
        SELECT RAISE(ABORT, 'terminal attempt is immutable');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_terminal_requires_detached_task
      BEFORE UPDATE OF state ON workflow_attempts
      WHEN NEW.state <> 'started' AND EXISTS (
        SELECT 1 FROM tasks WHERE active_attempt_id = OLD.id
      )
      BEGIN
        SELECT RAISE(ABORT, 'task must release its active attempt before completion');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_no_delete
      BEFORE DELETE ON workflow_attempts
      BEGIN
        SELECT RAISE(ABORT, 'attempt cannot be deleted');
      END;
    SQL
  end

  def reconciliation_attachment_exception(allowed)
    return "" unless allowed

    <<~SQL.squish.prepend(" AND NOT (").concat(")")
      OLD.state = 'interrupted'
      AND OLD.reconciliation_state IS NULL
      AND OLD.reconciliation_evidence_digest IS NULL
      AND OLD.reconciled_at IS NULL
      AND OLD.legacy_reconciliation_pending = 1
      AND NEW.reconciliation_state IS NOT NULL
      AND NEW.reconciliation_evidence_digest IS NOT NULL
      AND NEW.reconciled_at IS NOT NULL
      AND NEW.legacy_reconciliation_pending = 0
      AND NEW.id IS OLD.id
      AND NEW.repository_id IS OLD.repository_id
      AND NEW.task_id IS OLD.task_id
      AND NEW.workflow_state_id IS OLD.workflow_state_id
      AND NEW.owner_id IS OLD.owner_id
      AND NEW.idempotency_key IS OLD.idempotency_key
      AND NEW.state IS OLD.state
      AND NEW.fencing_token IS OLD.fencing_token
      AND NEW.lease_expires_at IS OLD.lease_expires_at
      AND NEW.heartbeat_at IS OLD.heartbeat_at
      AND NEW.started_at IS OLD.started_at
      AND NEW.completed_at IS OLD.completed_at
      AND NEW.input_context IS OLD.input_context
      AND NEW.input_context_digest IS OLD.input_context_digest
      AND NEW.result_manifest IS OLD.result_manifest
      AND NEW.created_at IS OLD.created_at
    SQL
  end

  def restore_reconciliation_pending_triggers
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_legacy_reconciliation_pending_insert
      BEFORE INSERT ON workflow_attempts
      WHEN NEW.legacy_reconciliation_pending <> 0
      BEGIN
        SELECT RAISE(ABORT, 'legacy reconciliation marker cannot be created');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_legacy_reconciliation_pending_update
      BEFORE UPDATE OF legacy_reconciliation_pending ON workflow_attempts
      WHEN NOT (
        OLD.state = 'interrupted'
        AND OLD.legacy_reconciliation_pending = 1
        AND NEW.legacy_reconciliation_pending = 0
        AND NEW.reconciliation_state IS NOT NULL
        AND NEW.reconciliation_evidence_digest IS NOT NULL
        AND NEW.reconciled_at IS NOT NULL
      )
      BEGIN
        SELECT RAISE(ABORT, 'legacy reconciliation marker is immutable');
      END;
    SQL
  end
end
