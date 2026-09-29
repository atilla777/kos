class CreateTaskGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :task_groups do |t|
      t.references :project, null: false, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.string :title, null: false
      t.text :description, null: false

      t.timestamps
    end

    add_check_constraint :task_groups, "kind = 'epic'", name: "task_groups_kind_allowed"
    add_check_constraint :task_groups, "length(trim(title)) > 0", name: "task_groups_title_present"
    add_check_constraint :task_groups, "length(trim(description)) > 0", name: "task_groups_description_present"
    add_index :task_groups, %i[id project_id], unique: true

    add_reference :tasks, :task_group, index: true
    add_foreign_key :tasks, :task_groups,
      column: %i[task_group_id project_id],
      primary_key: %i[id project_id],
      on_delete: :restrict
  end
end
