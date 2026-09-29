class StrengthenTaskOwnershipConstraint < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :tasks, name: "tasks_status_ownership_consistent"
    add_check_constraint :tasks,
      <<~SQL.squish,
        (status = 'in_progress'
          AND session_id IS NOT NULL AND length(trim(session_id)) > 0
          AND claim_id IS NOT NULL AND length(trim(claim_id)) > 0
          AND claimed_at IS NOT NULL AND lease_expires_at IS NOT NULL
          AND lease_expires_at > claimed_at)
        OR
        (status IN ('planned', 'done') AND session_id IS NULL AND claim_id IS NULL
          AND claimed_at IS NULL AND lease_expires_at IS NULL)
      SQL
      name: "tasks_status_ownership_consistent"
  end

  def down
    remove_check_constraint :tasks, name: "tasks_status_ownership_consistent"
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
