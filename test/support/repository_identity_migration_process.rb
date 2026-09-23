require "active_record"
require "json"
require_relative "../../app/models/repository_identity"

database, scenario = ARGV
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database:)
connection = ActiveRecord::Base.connection
connection.create_table(:projects) do |table|
  table.string :name, null: false
  table.string :remote_url, null: false
  table.string :default_branch, null: false
  table.timestamps null: false
end
connection.create_table(:workflows) do |table|
  table.string :name, null: false
  table.json :definition_json, null: false
  table.datetime :created_at, null: false
end
connection.create_table(:task_types) do |table|
  table.string :key, null: false
  table.string :name, null: false
  table.integer :workflow_id, null: false
  table.timestamps null: false
end
connection.create_table(:tasks) do |table|
  table.integer :project_id, null: false
  table.integer :task_type_id, null: false
  table.integer :workflow_id, null: false
  table.integer :parent_id
  table.string :title, null: false
  table.text :description_markdown, null: false
  table.string :status, null: false
  table.string :current_step, null: false
  table.string :owner_id
  table.integer :claim_version, null: false
  table.datetime :lease_expires_at
  table.json :accepted_artifacts, null: false
  table.text :pause_message
  table.string :pause_step
  table.integer :pause_claim_version
  table.text :human_answer
  table.string :human_answer_step
  table.integer :human_answer_claim_version
  table.timestamps null: false
end
connection.create_table(:task_dependencies, id: false) do |table|
  table.integer :task_id, null: false
  table.integer :blocker_id, null: false
end
connection.add_foreign_key :task_types, :workflows
connection.add_foreign_key :tasks, :projects
connection.add_foreign_key :tasks, :task_types
connection.add_foreign_key :tasks, :workflows
connection.add_foreign_key :tasks, :tasks, column: :parent_id
connection.add_foreign_key :task_dependencies, :tasks
connection.add_foreign_key :task_dependencies, :tasks, column: :blocker_id

class Project < ActiveRecord::Base; end

remotes = case scenario
when "valid"
  [ "https://github.com/acme/kos.git", "git@github.com:acme/other.git" ]
when "malformed"
  [ "https://github.com/acme/kos.git", "file:///tmp/other" ]
when "colliding"
  [ "https://github.com/acme/kos.git", "git@github.com:acme/kos.git" ]
end
remotes.each_with_index do |remote, index|
  connection.execute("INSERT INTO projects (id, name, remote_url, default_branch, created_at, updated_at) " \
    "VALUES (#{11 + index}, 'Project #{index}', #{connection.quote(remote)}, 'main', '2026-09-01 00:00:00', '2026-09-01 00:00:00')")
end
connection.execute("INSERT INTO workflows (id, name, definition_json, created_at) " \
  "VALUES (7, 'Snapshot', '{\"steps\":[{\"id\":\"plan\"}]}', '2026-09-01 00:00:00')")
connection.execute("INSERT INTO task_types (id, key, name, workflow_id, created_at, updated_at) " \
  "VALUES (5, 'development', 'Development', 7, '2026-09-01 00:00:00', '2026-09-01 00:00:00')")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id, title, description_markdown, status, " \
  "current_step, claim_version, accepted_artifacts, created_at, updated_at) VALUES " \
  "(22, 11, 5, 7, 'Parent', 'Parent description', 'completed', 'verify', 3, '{}', '2026-09-01 00:00:00', '2026-09-01 00:00:00')")
connection.execute("INSERT INTO tasks (id, project_id, task_type_id, workflow_id, parent_id, title, description_markdown, " \
  "status, current_step, owner_id, claim_version, lease_expires_at, accepted_artifacts, pause_message, pause_step, " \
  "pause_claim_version, human_answer, human_answer_step, human_answer_claim_version, created_at, updated_at) VALUES " \
  "(21, 11, 5, 7, 22, 'Active task', 'Description', 'blocked', 'review', 'owner-21', 9, '2026-10-01 00:00:00', " \
  "'{\"plan\":{\"outcome\":\"planned\"}}', 'Network unavailable', 'review', 8, 'Use retry', 'review', 7, " \
  "'2026-09-02 00:00:00', '2026-09-03 00:00:00')")
connection.execute("INSERT INTO task_dependencies (task_id, blocker_id) VALUES (21, 22)")

task_sql = "SELECT id, project_id, task_type_id, workflow_id, parent_id, title, description_markdown, status, " \
  "current_step, owner_id, claim_version, lease_expires_at, accepted_artifacts, pause_message, pause_step, " \
  "pause_claim_version, human_answer, human_answer_step, human_answer_claim_version, created_at, updated_at FROM tasks WHERE id = 21"

require_relative "../../db/migrate/20260922000000_add_repository_identity_to_projects"
error = nil
begin
  AddRepositoryIdentityToProjects.new.migrate(:up)
rescue StandardError => exception
  error = exception.message
end

columns = connection.columns(:projects).map(&:name)
result = {
  error:,
  columns:,
  projects: connection.select_rows("SELECT id, remote_url FROM projects ORDER BY id"),
  identities: columns.include?("repository_identity") ? connection.select_values("SELECT repository_identity FROM projects ORDER BY id") : [],
  task: connection.select_rows(task_sql).first,
  dependencies: connection.select_rows("SELECT task_id, blocker_id FROM task_dependencies"),
  workflow: connection.select_rows("SELECT id, name, definition_json, created_at FROM workflows").first
}
if error.nil?
  AddRepositoryIdentityToProjects.new.migrate(:down)
  result[:down_columns] = connection.columns(:projects).map(&:name)
  result[:task_after_down] = connection.select_rows(task_sql).first
  result[:dependencies_after_down] = connection.select_rows("SELECT task_id, blocker_id FROM task_dependencies")
end
puts JSON.generate(result)
