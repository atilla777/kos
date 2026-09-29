require "test_helper"

class TaskClaimConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Project.delete_all
  end

  test "two sessions cannot both claim the same task" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    task = project.tasks.create!(kind: "feature", title: "Claim", description: "Claim.")

    outcomes = concurrently("agent-1", "agent-2") do |session_id|
      Task.claim_for!(project: Project.find(project.id), task_id: task.id, session_id: session_id)
      :claimed
    rescue Task::ClaimError => error
      error.code
    end

    assert_equal 1, outcomes.count(:claimed)
    assert_equal 1, outcomes.count("task_already_claimed")
    assert_equal "in_progress", task.reload.status
    assert_match(/\A[0-9a-f]{64}\z/, task.claim_id)
  end

  test "concurrent claim-next requests from one session return one task" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    2.times do |index|
      project.tasks.create!(kind: "feature", title: "Task #{index}", description: "Claim.")
    end

    outcomes = concurrently("agent-1", "agent-1") do |session_id|
      claimed_task, reused = Task.claim_next_for!(project: Project.find(project.id), session_id: session_id)
      [ claimed_task.id, reused ]
    end

    assert_equal 1, outcomes.map(&:first).uniq.length
    assert_equal [ false, true ], outcomes.map(&:last).sort_by(&:to_s)
    assert_equal 1, project.tasks.where(status: "in_progress").count
  end

  test "one session cannot explicitly claim two tasks concurrently" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    tasks = 2.times.map do |index|
      project.tasks.create!(kind: "feature", title: "Task #{index}", description: "Claim.")
    end

    outcomes = concurrently(*tasks.map(&:id)) do |task_id|
      Task.claim_for!(project: Project.find(project.id), task_id: task_id, session_id: "agent-1")
      :claimed
    rescue Task::ClaimError => error
      error.code
    end

    assert_equal 1, outcomes.count(:claimed)
    assert_equal 1, outcomes.count("session_has_active_task")
    assert_equal 1, project.tasks.where(status: "in_progress", session_id: "agent-1").count
  end

  test "reopen cannot race with dependent work starting" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    blocker = project.tasks.create!(kind: "feature", title: "Result", description: "Result.")
    dependent = project.tasks.create!(kind: "feature", title: "Consumer", description: "Consumer.")
    dependent.replace_blockers!([ blocker.id ])
    blocker.update_columns(status: "done")

    outcomes = concurrently(:reopen, :claim) do |operation|
      if operation == :reopen
        Task.find(blocker.id).reopen!
        :reopened
      else
        Task.claim_for!(project: Project.find(project.id), task_id: dependent.id, session_id: "agent-1")
        :claimed
      end
    rescue Task::ClaimError => error
      error.code
    end

    assert_equal 1, outcomes.count { |outcome| %i[reopened claimed].include?(outcome) }
    assert outcomes.include?("task_blocked") || outcomes.include?("task_has_started_dependents")
    refute blocker.reload.status == "planned" && dependent.reload.status == "in_progress"
  end

  test "a stale planned snapshot cannot replace blockers after the task is claimed" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    blocker = project.tasks.create!(kind: "feature", title: "Blocker", description: "Blocker.")
    blocker.update_columns(status: "done")
    task = project.tasks.create!(kind: "feature", title: "Work", description: "Work.")
    stale_task = Task.find(task.id)

    Task.claim_for!(project: project, task_id: task.id, session_id: "agent-1")

    assert_raises(ActiveRecord::RecordInvalid) { stale_task.replace_blockers!([ blocker.id ]) }
    assert_empty task.reload.blocking_task_ids
  end

  private

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
