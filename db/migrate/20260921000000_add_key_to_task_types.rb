class AddKeyToTaskTypes < ActiveRecord::Migration[8.1]
  RESERVED_KEYS = %w[brief development fix].freeze

  class MigrationTaskType < ActiveRecord::Base
    self.table_name = "task_types"
  end

  def up
    add_column :task_types, :key, :string unless column_exists?(:task_types, :key)
    MigrationTaskType.reset_column_information

    rows = MigrationTaskType.order(:id).pluck(:id, :key)
    validate_existing_keys!(rows)
    rows.each do |id, key|
      MigrationTaskType.where(id:).update_all(key: custom_key(id)) if key.nil?
    end

    add_index :task_types, :key, unique: true unless index_exists?(:task_types, :key, unique: true)
    change_column_null :task_types, :key, false
  end

  def down
    remove_index :task_types, :key if index_exists?(:task_types, :key)
    remove_column :task_types, :key if column_exists?(:task_types, :key)
  end

  private

  def validate_existing_keys!(rows)
    keys = rows.map(&:second)
    return if keys.all?(&:nil?)

    if keys.any?(&:nil?) || rows.any? { |id, key| RESERVED_KEYS.include?(key) || key != custom_key(id) }
      raise ActiveRecord::MigrationError,
        "task type keys are partially migrated or collide with reserved built-in keys"
    end
  end

  def custom_key(id)
    "custom-#{id}"
  end
end
