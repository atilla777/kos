require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "seed installs current editions and replaces only unused definitions" do
    seed = Rails.root.join("db/seeds.rb")
    load seed
    definitions = Workflow.where(project_id: nil).order(:name)
    assert_equal [ "KOS Brief v2", "KOS Execution v2", "KOS Fix v2" ], definitions.pluck(:name)
    assert_equal [ 3, 5, 6 ], definitions.map { |workflow| workflow.steps.length }
    assert definitions.all?(&:valid?)

    ids = definitions.pluck(:id)
    load seed
    assert_equal ids, Workflow.where(project_id: nil).order(:name).pluck(:id)

    brief = definitions.first
    old_id = brief.id
    brief.update_columns(steps: [ { "name" => "Changed" } ])
    load seed
    assert_not_equal old_id, Workflow.find_by!(name: brief.name, project_id: nil).id
    assert_equal 3, Workflow.where(project_id: nil).count
  end

  test "seed refuses to replace a workflow in use and rolls back all changes" do
    load Rails.root.join("db/seeds.rb")
    brief = Workflow.find_by!(name: "KOS Brief v2", project_id: nil)
    Task.create!(project: Project.create!(repository: "github.com/workflow/seed", name: "Seed"),
      workflow: brief, title: "Keep existing route", description: "Do not replace this workflow", kind: "feature")
    obsolete = Workflow.create!(name: "KOS Fix v1", steps: Workflow.find_by!(name: "KOS Fix v2").steps)
    brief.update_columns(steps: [ { "name" => "Legacy" } ])

    error = assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb") }
    assert_includes error.message, "in use"
    assert_equal [ { "name" => "Legacy" } ], brief.reload.steps
    assert_equal brief.id, Task.last.workflow_id
    assert Workflow.exists?(obsolete.id)
  end

  test "seed retains used prior editions and removes unused ones without changing task steps" do
    old_brief = Workflow.create!(name: "KOS Brief v1", steps: JSON.parse(Rails.root.join("config/workflows/brief.json").read).fetch("steps"))
    old_execution = Workflow.create!(name: "KOS Execution v1", steps: JSON.parse(Rails.root.join("config/workflows/execution.json").read).fetch("steps"))
    old_fix = Workflow.create!(name: "KOS Fix v1", steps: JSON.parse(Rails.root.join("config/workflows/fix.json").read).fetch("steps"))
    project = Project.create!(repository: "github.com/workflow/old", name: "Old")
    brief_task = Task.create!(project: project, workflow: old_brief, title: "Existing brief", description: "Keep route", kind: "decomposition")
    execution_task = Task.create!(project: project, workflow: old_execution, title: "Existing execution", description: "Keep route", kind: "feature")
    execution_task.update_columns(current_step: 1)
    artifact = TaskArtifact.create!(task: execution_task, key: "implementation_plan", content: "# Existing plan")
    original_steps = [ old_brief.steps, old_execution.steps ]

    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal [ old_brief.id, old_execution.id ], [ brief_task.reload.workflow_id, execution_task.reload.workflow_id ]
    assert_equal original_steps, [ old_brief.reload.steps, old_execution.reload.steps ]
    assert_not Workflow.exists?(old_fix.id)
    assert_equal 5, Workflow.where(project_id: nil).count
    assert_equal 0, brief_task.current_step
    assert_equal 1, execution_task.reload.current_step
    assert_equal "# Existing plan", artifact.reload.content
    assert Workflow.exists?(name: "KOS Brief v2", project_id: nil)
    assert Workflow.exists?(name: "KOS Execution v2", project_id: nil)
    assert Workflow.exists?(name: "KOS Fix v2", project_id: nil)
  end
end
