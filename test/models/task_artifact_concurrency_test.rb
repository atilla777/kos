require "test_helper"

class TaskArtifactConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskArtifact.delete_all
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Project.delete_all
  end

  teardown do
    TaskArtifact.delete_all
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Project.delete_all
  end

  test "two updates of one version preserve the first committed result" do
    project, task = create_claimed_task
    artifact = task.put_artifact!(
      key: "specification", content: "Initial", claim_id: task.claim_id, expected_lock_version: nil
    )

    outcomes = concurrently("First", "Second") do |content|
      current_task = Task.find(task.id)
      current_task.put_artifact!(
        key: artifact.key,
        content: content,
        claim_id: task.claim_id,
        expected_lock_version: artifact.lock_version
      )
      :saved
    rescue TaskArtifact::VersionConflict
      :conflict
    end

    assert_equal 1, outcomes.count(:saved)
    assert_equal 1, outcomes.count(:conflict)
    assert_includes [ "First", "Second" ], artifact.reload.content
    assert_equal 1, artifact.lock_version
  end

  test "concurrent creation of one key creates one row" do
    _project, task = create_claimed_task

    outcomes = concurrently("First", "Second") do |content|
      Task.find(task.id).put_artifact!(
        key: "report", content: content, claim_id: task.claim_id, expected_lock_version: nil
      )
      :saved
    rescue TaskArtifact::VersionConflict
      :conflict
    end

    assert_equal 1, outcomes.count(:saved)
    assert_equal 1, outcomes.count(:conflict)
    assert_equal 1, TaskArtifact.where(task_id: task.id, key: "report").count
  end

  private

  def create_claimed_task
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    task = project.tasks.create!(kind: "feature", title: "Artifacts", description: "Store results.")
    claimed_task, = Task.claim_for!(project: project, task_id: task.id, session_id: "agent-1")
    [ project, claimed_task ]
  end

  def concurrently(*values)
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = values.map do |value|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          result = yield(value)
        rescue StandardError => error
          result = error
        ensure
          results << result
        end
      end
    end

    values.length.times { ready.pop }
    values.length.times { start << true }
    threads.each(&:join)
    outcomes = values.length.times.map { results.pop }
    raise outcomes.grep(StandardError).first if outcomes.any?(StandardError)

    outcomes
  end
end
