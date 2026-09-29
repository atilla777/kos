class CreateWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :workflows do |t|
      t.references :project, null: false, foreign_key: { on_delete: :restrict }
      t.string :name, null: false
      t.json :steps, null: false
      t.timestamps
    end

    add_index :workflows, %i[id project_id], unique: true
    add_check_constraint :workflows, "length(trim(name)) > 0", name: "workflows_name_present"

    # Tasks from the pre-workflow local MVP have no defined step. The expansion
    # explicitly starts with an empty task set; projects and groups survive.
    execute "DELETE FROM task_dependencies"
    execute "DELETE FROM tasks"

    add_reference :tasks, :workflow, null: false, foreign_key: false
    add_column :tasks, :current_step, :integer, null: false, default: 0
    add_check_constraint :tasks, "current_step >= 0", name: "tasks_current_step_nonnegative"
    add_foreign_key :tasks, :workflows,
      column: %i[workflow_id project_id], primary_key: %i[id project_id], on_delete: :restrict
  end
end
