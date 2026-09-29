require "test_helper"

class TaskDependencyConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    TaskDependency.delete_all
    Task.delete_all
    TaskGroup.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "concurrent opposite dependencies cannot commit a cycle" do
    project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    first = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "First", description: "First.")
    second = project.tasks.create!(workflow: workflow_for(project), kind: "feature", title: "Second", description: "Second.")
    ready = Queue.new
    start = Queue.new
    results = Queue.new

    threads = [ [ first.id, second.id ], [ second.id, first.id ] ].map do |task_id, blocker_id|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          task = Task.find(task_id)
          ready << true
          start.pop
          task.replace_blockers!([ blocker_id ])
          results << :committed
        rescue Task::DependencyCycleError
          results << :cycle_rejected
        rescue StandardError => error
          results << error
        end
      end
    end

    2.times { ready.pop }
    2.times { start << true }
    threads.each(&:join)

    outcomes = 2.times.map { results.pop }
    raise outcomes.grep(StandardError).first if outcomes.any?(StandardError)

    assert_equal 1, outcomes.count(:committed)
    assert_equal 1, outcomes.count(:cycle_rejected)
    assert_equal 1, TaskDependency.count
    dependency = TaskDependency.sole
    assert_not TaskDependency.exists?(
      task_id: dependency.blocking_task_id,
      blocking_task_id: dependency.task_id
    )
  end
end
