class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.references :project, null: false, foreign_key: { on_delete: :restrict }
      t.string :kind, null: false
      t.string :title, null: false
      t.text :description, null: false
      t.string :status, null: false, default: "planned"
      t.text :work_summary
      t.string :session_id
      t.string :claim_id
      t.datetime :claimed_at
      t.datetime :lease_expires_at

      t.timestamps
    end

    add_check_constraint :tasks, "length(trim(kind)) > 0", name: "tasks_kind_present"
    add_check_constraint :tasks, "length(trim(title)) > 0", name: "tasks_title_present"
    add_check_constraint :tasks, "length(trim(description)) > 0", name: "tasks_description_present"
    add_check_constraint :tasks,
      "status IN ('planned', 'in_progress', 'done')",
      name: "tasks_status_allowed"
  end
end
