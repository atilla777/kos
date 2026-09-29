class AddTaskClaimIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :tasks, :claim_id, unique: true, where: "claim_id IS NOT NULL"
    add_index :tasks, %i[project_id session_id lease_expires_at],
      name: "index_tasks_on_project_session_and_lease",
      where: "status = 'in_progress'"
  end
end
