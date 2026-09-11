class CreateRuntimeConfigs < ActiveRecord::Migration[8.1]
  def up
    create_table :runtime_configs do |table|
      table.boolean :retrospective_enabled, null: false, default: false
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.check_constraint "id = 1", name: "runtime_configs_singleton"
    end

    execute <<~SQL.squish
      INSERT INTO runtime_configs (id, retrospective_enabled, lock_version, created_at, updated_at)
      VALUES (1, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down
    drop_table :runtime_configs
  end
end
