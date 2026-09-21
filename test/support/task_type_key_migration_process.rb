require "active_record"
require "json"

database, scenario = ARGV
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database:)
connection = ActiveRecord::Base.connection
connection.create_table(:workflows) { |table| table.string :name, null: false }
connection.create_table(:task_types) do |table|
  table.string :name, null: false
  table.integer :workflow_id, null: false
  table.timestamps null: false
end
connection.create_table(:tasks) do |table|
  table.integer :task_type_id, null: false
  table.integer :workflow_id, null: false
end

connection.execute("INSERT INTO workflows (id, name) VALUES (7, 'Original')")
connection.execute("INSERT INTO task_types (id, name, workflow_id, created_at, updated_at) " \
  "VALUES (11, 'Brief', 7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP), " \
  "(12, 'Development', 7, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)")
connection.execute("INSERT INTO tasks (id, task_type_id, workflow_id) VALUES (21, 11, 7)")

unless scenario == "legacy"
  connection.add_column(:task_types, :key, :string)
  values = case scenario
  when "reserved" then { 11 => "brief", 12 => "custom-12" }
  when "partial" then { 11 => "custom-11", 12 => nil }
  when "complete" then { 11 => "custom-11", 12 => "custom-12" }
  end
  values.each do |id, key|
    connection.execute("UPDATE task_types SET key = #{connection.quote(key)} WHERE id = #{id}")
  end
end

require_relative "../../db/migrate/20260921000000_add_key_to_task_types"

error = nil
begin
  AddKeyToTaskTypes.new.migrate(:up)
rescue StandardError => exception
  error = exception.message
end

columns = connection.columns(:task_types)
puts JSON.generate(
  error:,
  rows: connection.select_rows("SELECT id, name, workflow_id, key FROM task_types ORDER BY id"),
  task: connection.select_rows("SELECT task_type_id, workflow_id FROM tasks").first,
  key_null: columns.find { |column| column.name == "key" }&.null,
  key_indexes: connection.indexes(:task_types).count { |index| index.columns == [ "key" ] && index.unique }
)
