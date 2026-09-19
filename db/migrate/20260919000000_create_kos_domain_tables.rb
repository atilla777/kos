class CreateKosDomainTables < ActiveRecord::Migration[8.1]
  TASK_STATUSES = %w[pending active needs_human blocked completed cancelled].freeze

  def change
    create_table :projects do |table|
      table.string :name, null: false
      table.string :remote_url, null: false
      table.string :default_branch, null: false
      table.timestamps
    end

    create_table :workflows do |table|
      table.string :name, null: false
      table.json :definition_json, null: false
      table.datetime :created_at, null: false
    end

    create_table :task_types do |table|
      table.string :name, null: false
      table.references :workflow, null: false, foreign_key: true
      table.timestamps
    end

    create_table :tasks do |table|
      table.references :project, null: false, foreign_key: true
      table.references :task_type, null: false, foreign_key: true
      table.references :workflow, null: false, foreign_key: true
      table.references :parent, foreign_key: { to_table: :tasks }
      table.string :title, null: false
      table.text :description_markdown, null: false
      table.string :status, null: false, default: "pending"
      table.string :current_step, null: false
      table.string :owner_id
      table.integer :claim_version, null: false, default: 0
      table.datetime :lease_expires_at
      table.timestamps

      table.check_constraint "status IN (#{TASK_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
        name: "tasks_status"
      table.check_constraint "claim_version >= 0", name: "tasks_claim_version_nonnegative"
    end

    create_table :task_dependencies do |table|
      table.references :task, null: false, foreign_key: true
      table.references :blocker, null: false, foreign_key: { to_table: :tasks }
      table.index %i[task_id blocker_id], unique: true
    end
  end
end
