class AddWorkflowOrigin < ActiveRecord::Migration[8.1]
  def change
    reversible do |direction|
      direction.down do
        execute <<~SQL
          CREATE TRIGGER workflows_project_immutable
          BEFORE UPDATE OF project_id ON workflows
          WHEN OLD.project_id IS NOT NEW.project_id
          BEGIN
            SELECT RAISE(ABORT, 'workflow project cannot change');
          END;
        SQL
      end
    end
    add_reference :workflows, :base_workflow, foreign_key: { to_table: :workflows, on_delete: :restrict }
    add_column :workflows, :edition, :integer
    add_check_constraint :workflows, "edition IS NULL OR edition > 0", name: "workflows_edition_positive"
    add_check_constraint :workflows, "(base_workflow_id IS NULL AND edition IS NULL) OR (base_workflow_id IS NOT NULL AND edition IS NOT NULL AND project_id IS NOT NULL)", name: "workflows_origin_complete"
    add_index :workflows, %i[project_id base_workflow_id edition], unique: true, name: "index_workflows_on_project_origin_edition"
    # Adding SQLite check constraints rebuilds the table and drops its triggers.
    reversible do |direction|
      direction.up do
        execute <<~SQL
          CREATE TRIGGER workflows_project_immutable
          BEFORE UPDATE OF project_id ON workflows
          WHEN OLD.project_id IS NOT NEW.project_id
          BEGIN
            SELECT RAISE(ABORT, 'workflow project cannot change');
          END;
        SQL
        %w[INSERT UPDATE].each do |action|
          execute <<~SQL
            CREATE TRIGGER workflows_base_#{action.downcase}
            BEFORE #{action} ON workflows
            WHEN NEW.base_workflow_id IS NOT NULL AND NOT EXISTS (
              SELECT 1 FROM workflows WHERE id = NEW.base_workflow_id
                AND project_id IS NULL AND base_workflow_id IS NULL
            )
            BEGIN
              SELECT RAISE(ABORT, 'base workflow must be shared');
            END;
          SQL
        end
        execute <<~SQL
          CREATE TRIGGER workflows_origin_immutable
          BEFORE UPDATE OF base_workflow_id, edition ON workflows
          WHEN OLD.base_workflow_id IS NOT NEW.base_workflow_id OR OLD.edition IS NOT NEW.edition
          BEGIN
            SELECT RAISE(ABORT, 'workflow origin and edition cannot change');
          END;
        SQL
      end
      direction.down do
        execute "DROP TRIGGER IF EXISTS workflows_origin_immutable"
        execute "DROP TRIGGER IF EXISTS workflows_base_update"
        execute "DROP TRIGGER IF EXISTS workflows_base_insert"
        execute "DROP TRIGGER IF EXISTS workflows_project_immutable"
      end
    end
  end
end
