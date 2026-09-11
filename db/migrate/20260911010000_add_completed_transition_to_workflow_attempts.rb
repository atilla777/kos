class AddCompletedTransitionToWorkflowAttempts < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE workflow_attempts
      ADD COLUMN completed_transition_id varchar REFERENCES workflow_transitions(id)
    SQL
    add_index :workflow_attempts, :completed_transition_id

    execute <<~SQL
      CREATE TRIGGER workflow_attempts_completed_transition_insert
      BEFORE INSERT ON workflow_attempts
      WHEN NEW.state = 'succeeded' OR NEW.completed_transition_id IS NOT NULL
      BEGIN
        SELECT RAISE(ABORT, 'a new attempt cannot be inserted as succeeded or with a completed transition');
      END;
    SQL
    execute <<~SQL
      CREATE TRIGGER workflow_attempts_completed_transition_update
      BEFORE UPDATE OF state, completed_transition_id ON workflow_attempts
      WHEN (NEW.state = 'succeeded' AND (
        NEW.completed_transition_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM workflow_transitions transition_record
          JOIN tasks ON tasks.id = NEW.task_id AND tasks.repository_id = NEW.repository_id
          WHERE transition_record.id = NEW.completed_transition_id
            AND transition_record.from_state_id = NEW.workflow_state_id
            AND transition_record.to_state_id = tasks.workflow_state_id
            AND transition_record.workflow_version_id = tasks.workflow_version_id
        )
      )) OR (NEW.state <> 'succeeded' AND NEW.completed_transition_id IS NOT NULL)
      BEGIN
        SELECT RAISE(ABORT, 'completed transition must match a succeeded attempt and advanced task');
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS workflow_attempts_completed_transition_update"
    execute "DROP TRIGGER IF EXISTS workflow_attempts_completed_transition_insert"
    remove_index :workflow_attempts, :completed_transition_id
    execute "ALTER TABLE workflow_attempts DROP COLUMN completed_transition_id"
  end
end
