class AllowGlobalWorkflows < ActiveRecord::Migration[8.1]
  def up
    preserve_task_children do
      remove_foreign_key :tasks, :workflows, column: %i[workflow_id project_id]
      change_column_null :workflows, :project_id, true
      add_foreign_key :tasks, :workflows, column: :workflow_id, on_delete: :restrict
    end

    %w[INSERT UPDATE].each do |action|
      execute <<~SQL
        CREATE TRIGGER tasks_workflow_project_#{action.downcase}
        BEFORE #{action} ON tasks
        WHEN EXISTS (
          SELECT 1 FROM workflows
          WHERE id = NEW.workflow_id AND project_id IS NOT NULL AND project_id != NEW.project_id
        )
        BEGIN
          SELECT RAISE(ABORT, 'workflow must belong to the task project');
        END;
      SQL
    end
    execute <<~SQL
      CREATE TRIGGER workflows_project_immutable
      BEFORE UPDATE OF project_id ON workflows
      WHEN OLD.project_id IS NOT NEW.project_id
      BEGIN
        SELECT RAISE(ABORT, 'workflow project cannot change');
      END;
    SQL
  end

  def down
    execute "DROP TRIGGER workflows_project_immutable"
    execute "DROP TRIGGER tasks_workflow_project_update"
    execute "DROP TRIGGER tasks_workflow_project_insert"

    preserve_task_children do
      remove_foreign_key :tasks, :workflows, column: :workflow_id
      change_column_null :workflows, :project_id, false
      add_foreign_key :tasks, :workflows,
        column: %i[workflow_id project_id], primary_key: %i[id project_id], on_delete: :restrict
    end
  end

  private

  # SQLite rebuilds tasks when changing its foreign key. Dropping the old table
  # cascades into children even inside Rails' referential-integrity wrapper.
  def preserve_task_children
    %w[task_dependencies task_artifacts].each do |table|
      execute "CREATE TEMP TABLE saved_#{table} AS SELECT * FROM #{table}"
      execute "DELETE FROM #{table}"
    end
    yield
    %w[task_dependencies task_artifacts].each do |table|
      execute "INSERT INTO #{table} SELECT * FROM saved_#{table}"
      execute "DROP TABLE saved_#{table}"
    end
  end
end
