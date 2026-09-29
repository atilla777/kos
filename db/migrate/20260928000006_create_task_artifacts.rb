class CreateTaskArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :task_artifacts do |t|
      t.references :task, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.text :content, null: false
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :task_artifacts, %i[task_id key], unique: true
    add_check_constraint :task_artifacts,
      "length(trim(key)) > 0",
      name: "task_artifacts_key_not_blank"
    add_check_constraint :task_artifacts,
      "lock_version >= 0",
      name: "task_artifacts_lock_version_not_negative"
  end
end
