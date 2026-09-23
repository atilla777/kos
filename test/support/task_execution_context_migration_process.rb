require "active_record"
require "json"

database = ARGV.fetch(0)
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database:)
connection = ActiveRecord::Base.connection
connection.execute("PRAGMA foreign_keys = ON")
connection.create_table(:projects) { |table| table.string :name }
connection.create_table(:workflows) { |table| table.json :definition_json }
connection.create_table(:task_types) do |table|
  table.integer :workflow_id, null: false
  table.foreign_key :workflows
end
connection.create_table(:tasks) do |table|
  table.integer :project_id, null: false
  table.integer :task_type_id, null: false
  table.integer :workflow_id, null: false
  table.integer :parent_id
  table.foreign_key :projects
  table.foreign_key :task_types
  table.foreign_key :workflows
  table.foreign_key :tasks, column: :parent_id
end
connection.create_table(:task_dependencies) do |table|
  table.integer :task_id, null: false
  table.integer :blocker_id, null: false
  table.foreign_key :tasks
  table.foreign_key :tasks, column: :blocker_id
end

connection.execute("INSERT INTO projects (id, name) VALUES (11, 'Project')")
connection.execute("INSERT INTO workflows (id, definition_json) VALUES (12, '{}')")
connection.execute("INSERT INTO task_types (id, workflow_id) VALUES (13, 12)")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id) VALUES (14, 11, 13, 12)")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id, parent_id) VALUES (15, 11, 13, 12, 14)")
connection.execute("INSERT INTO task_dependencies (id, task_id, blocker_id) VALUES (16, 15, 14)")

require_relative "../../db/migrate/20260923000000_add_task_execution_context"

migration = AddTaskExecutionContext.new
migration.migrate(:up)
after_up = {
  tables: connection.tables.sort,
  artifacts: JSON.parse(connection.select_value("SELECT accepted_artifacts FROM tasks WHERE id = 14")),
  ids: connection.select_rows("SELECT id, project_id, task_type_id, workflow_id, parent_id FROM tasks ORDER BY id"),
  dependency: connection.select_rows("SELECT id, task_id, blocker_id FROM task_dependencies")
}
migration.migrate(:down)

puts JSON.generate(after_up.merge(
  columns_after_down: connection.columns(:tasks).map(&:name),
  ids_after_down: connection.select_rows("SELECT id, project_id, task_type_id, workflow_id, parent_id FROM tasks ORDER BY id"),
  dependency_after_down: connection.select_rows("SELECT id, task_id, blocker_id FROM task_dependencies")
))
