class CreateTaskDependencies < ActiveRecord::Migration[8.1]
  def change
    add_index :tasks, %i[id project_id], unique: true

    create_table :task_dependencies do |t|
      t.integer :task_id, null: false
      t.integer :blocking_task_id, null: false
      t.integer :project_id, null: false

      t.timestamps
    end

    add_index :task_dependencies, %i[task_id blocking_task_id], unique: true
    add_index :task_dependencies, %i[task_id project_id]
    add_index :task_dependencies, %i[blocking_task_id project_id]
    add_check_constraint :task_dependencies,
      "task_id != blocking_task_id",
      name: "task_dependencies_not_self_referential"
    add_foreign_key :task_dependencies, :tasks,
      column: %i[task_id project_id],
      primary_key: %i[id project_id],
      on_delete: :cascade
    add_foreign_key :task_dependencies, :tasks,
      column: %i[blocking_task_id project_id],
      primary_key: %i[id project_id],
      on_delete: :restrict
  end
end
