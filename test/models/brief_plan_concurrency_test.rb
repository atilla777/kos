require "test_helper"

class BriefPlanConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    BriefPlan.delete_all
    TaskDependency.delete_all
    Task.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  teardown do
    BriefPlan.delete_all
    TaskDependency.delete_all
    Task.delete_all
    Workflow.delete_all
    Project.delete_all
  end

  test "two concurrent writes with the same key create exactly one set on SQLite" do
    project = Project.create!(name: "Plans", repository: "github.com/example/race")
    brief_workflow = project.workflows.create!(name: "KOS Brief v2", steps: [
      { name: "Plan", instructions: "Plan.", executor: "main", inputs: [], outputs: [] }
    ])
    execution = project.workflows.create!(name: "Execution", steps: [
      { name: "Work", instructions: "Work.", executor: "main", inputs: [], outputs: [] }
    ])
    brief = project.tasks.create!(workflow: brief_workflow, kind: "decomposition", title: "Brief", description: "Brief.")
    brief, = Task.claim_for!(project: project, task_id: brief.id, session_id: "owner")
    entries = [ { "name" => "first", "kind" => "feature", "title" => "First", "description" => "Work.",
      "workflow_id" => execution.id } ]

    ready = Queue.new
    start = Queue.new
    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          BriefPlan.create_for!(brief: Task.find(brief.id), claim_id: brief.claim_id,
            expected_step: 0, key: "same", entries: entries)
        end
      end
    end
    2.times { ready.pop }
    2.times { start << true }
    results = threads.map(&:value)

    assert_equal [ false, true ], results.map(&:last).sort_by(&:to_s)
    assert_equal 1, BriefPlan.count
    assert_equal 2, Task.count
    assert_equal results.first.first.result, results.last.first.result
    assert_equal [ brief.id ], Task.where.not(id: brief.id).sole.blocking_task_ids
  end
end
