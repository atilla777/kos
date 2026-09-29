require "test_helper"

class SqliteContentionTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  REPOSITORY = "github.com/atilla777/contention"

  setup do
    TaskArtifact.delete_all
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskArtifact.delete_all
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "a held SQLite write lock times out predictably without partial changes" do
    project = Project.create!(name: "Contention", repository: REPOSITORY)
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Claim", description: "Claim safely.")
    locked = Queue.new
    release = Queue.new

    holder = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        connection.execute("BEGIN IMMEDIATE TRANSACTION")
        locked << true
        release.pop
        connection.execute("ROLLBACK TRANSACTION")
      end
    end

    locked.pop
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    post "/api/v1/tasks/#{task.id}/claim", params: {
      project: REPOSITORY, session_id: "agent-1"
    }, as: :json
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

    assert_response :service_unavailable
    assert_equal "database_busy", response.parsed_body.dig("error", "code")
    assert_operator elapsed, :<, 7
    assert_equal "planned", task.reload.status

    release << true
    holder.join
    holder = nil

    post "/api/v1/tasks/#{task.id}/claim", params: {
      project: REPOSITORY, session_id: "agent-1"
    }, as: :json
    assert_response :ok
    assert_equal "in_progress", task.reload.status
  ensure
    release << true if holder&.alive?
    holder&.join
  end

  test "tests use the configured persistent SQLite guarantees" do
    connection = ActiveRecord::Base.connection

    assert_equal "SQLite", connection.adapter_name
    assert_not_equal ":memory:", ActiveRecord::Base.connection_db_config.database
    assert_equal 1, connection.select_value("PRAGMA foreign_keys").to_i
    assert_equal 5000, ActiveRecord::Base.connection_db_config.configuration_hash.fetch(:timeout)
  end
end
