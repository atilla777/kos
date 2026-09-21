class EnforceUniqueTaskOwner < ActiveRecord::Migration[8.1]
  def up
    invalid_owner = select_value(<<~SQL)
      SELECT owner_id
      FROM tasks
      WHERE owner_id IS NOT NULL
      GROUP BY owner_id
      HAVING TRIM(owner_id) = '' OR COUNT(*) > 1
      LIMIT 1
    SQL
    if invalid_owner
      raise ActiveRecord::MigrationError,
        "task owners contain blank or duplicate values; resolve active ownership before retrying the migration"
    end

    add_index :tasks, :owner_id, unique: true, where: "owner_id IS NOT NULL"
  end

  def down
    remove_index :tasks, :owner_id
  end
end
