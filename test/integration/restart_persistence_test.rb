require "test_helper"
require "open3"

class RestartPersistenceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

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

  test "a fresh application process reads lease progress and artifacts from SQLite in UTC" do
    project = Project.create!(name: "Restart", repository: "github.com/atilla777/restart")
    task = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Persist", description: "Persist state.")
    task, = Task.claim_for!(project: project, task_id: task.id, session_id: "agent-1")
    task.update_from_request!(attributes: { work_summary: "Work survives" }, claim_id: task.claim_id)
    artifact = task.put_artifact!(
      key: "report", content: "# Persistent", claim_id: task.claim_id, expected_lock_version: nil
    )

    code = <<~'RUBY'
      task = Task.find(ENV.fetch("KOS_RESTART_TASK_ID"))
      artifact = task.task_artifacts.find_by!(key: "report")
      puts JSON.generate(
        status: task.status,
        session_id: task.session_id,
        claim_id: task.claim_id,
        claimed_at: task.claimed_at.iso8601(6),
        lease_expires_at: task.lease_expires_at.iso8601(6),
        work_summary: task.work_summary,
        artifact_content: artifact.content,
        artifact_version: artifact.lock_version
      )
    RUBY
    stdout, stderr, status = Open3.capture3(
      {
        "RAILS_ENV" => "test",
        "KOS_TEST_DATABASE" => ActiveRecord::Base.connection_db_config.database,
        "KOS_RESTART_TASK_ID" => task.id.to_s
      },
      Rails.root.join("bin/rails").to_s,
      "runner",
      code
    )

    assert status.success?, stderr
    persisted = JSON.parse(stdout)
    assert_equal "in_progress", persisted.fetch("status")
    assert_equal "agent-1", persisted.fetch("session_id")
    assert_equal task.claim_id, persisted.fetch("claim_id")
    assert_equal task.claimed_at.iso8601(6), persisted.fetch("claimed_at")
    assert_equal task.lease_expires_at.iso8601(6), persisted.fetch("lease_expires_at")
    assert persisted.fetch("claimed_at").end_with?("Z")
    assert persisted.fetch("lease_expires_at").end_with?("Z")
    assert_equal "Work survives", persisted.fetch("work_summary")
    assert_equal "# Persistent", persisted.fetch("artifact_content")
    assert_equal artifact.lock_version, persisted.fetch("artifact_version")
  end
end
