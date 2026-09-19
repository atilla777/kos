require "test_helper"

class DomainSchemaTest < ActiveSupport::TestCase
  DOMAIN_TABLES = %w[projects workflows task_types tasks task_dependencies].freeze

  test "contains exactly the five domain tables" do
    internal_tables = %w[ar_internal_metadata schema_migrations]

    assert_equal DOMAIN_TABLES.sort, (ActiveRecord::Base.connection.tables - internal_tables).sort
  end

  test "defines required columns, optional ownership fields, and task defaults" do
    required_columns = {
      Project => %w[name remote_url default_branch created_at updated_at],
      Workflow => %w[name definition_json created_at],
      TaskType => %w[name workflow_id created_at updated_at],
      Task => %w[project_id task_type_id workflow_id title description_markdown status current_step
        claim_version created_at updated_at],
      TaskDependency => %w[task_id blocker_id]
    }

    required_columns.each do |model, column_names|
      column_names.each { |name| assert_equal false, model.columns_hash.fetch(name).null }
    end

    assert Task.columns_hash.fetch("parent_id").null
    assert Task.columns_hash.fetch("owner_id").null
    assert Task.columns_hash.fetch("lease_expires_at").null
    assert_equal "pending", Task.columns_hash.fetch("status").default
    assert_equal 0, Task.columns_hash.fetch("claim_version").default
  end

  test "defines every domain foreign key" do
    foreign_keys = DOMAIN_TABLES.flat_map do |table|
      ActiveRecord::Base.connection.foreign_keys(table).map do |foreign_key|
        [ table, foreign_key.options.fetch(:column), foreign_key.to_table ]
      end
    end

    assert_equal [
      [ "task_dependencies", "blocker_id", "tasks" ],
      [ "task_dependencies", "task_id", "tasks" ],
      [ "task_types", "workflow_id", "workflows" ],
      [ "tasks", "parent_id", "tasks" ],
      [ "tasks", "project_id", "projects" ],
      [ "tasks", "task_type_id", "task_types" ],
      [ "tasks", "workflow_id", "workflows" ]
    ], foreign_keys.sort
  end

  test "rejects invalid status and negative claim version in the database" do
    task = build_task

    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(status: "unknown") }
    assert_raises(ActiveRecord::StatementInvalid) { task.update_columns(claim_version: -1) }
  end

  test "enforces task foreign keys" do
    task = build_task

    assert_raises(ActiveRecord::InvalidForeignKey) { task.update_columns(project_id: -1) }
  end

  test "enforces one dependency per task and blocker pair" do
    task = build_task
    blocker = build_task
    TaskDependency.create!(task:, blocker:)

    assert_raises(ActiveRecord::RecordNotUnique) do
      TaskDependency.create!(task:, blocker:)
    end
  end

  test "exposes parent and blocking associations" do
    parent = build_task
    blocker = build_task
    task = build_task(parent:)
    TaskDependency.create!(task:, blocker:)

    assert_equal [ task ], parent.children.to_a
    assert_equal [ blocker ], task.blockers.to_a
    assert_equal [ task ], blocker.blocked_tasks.to_a
  end

  private

  def build_task(parent: nil)
    project = Project.create!(name: "Project", remote_url: "https://example.test/repository.git",
      default_branch: "main")
    workflow = Workflow.create!({ name: "Workflow", definition_json: {} })
    task_type = TaskType.create!(name: "Type", workflow:)

    Task.create!(project:, task_type:, workflow:, parent:, title: "Task",
      description_markdown: "Description", current_step: "develop")
  end
end
