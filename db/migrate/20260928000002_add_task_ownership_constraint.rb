class AddTaskOwnershipConstraint < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :tasks,
      <<~SQL.squish,
        (status = 'in_progress' AND session_id IS NOT NULL AND claim_id IS NOT NULL
          AND claimed_at IS NOT NULL AND lease_expires_at IS NOT NULL)
        OR
        (status IN ('planned', 'done') AND session_id IS NULL AND claim_id IS NULL
          AND claimed_at IS NULL AND lease_expires_at IS NULL)
      SQL
      name: "tasks_status_ownership_consistent"
  end
end
