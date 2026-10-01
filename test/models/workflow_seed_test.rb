require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "seed installs current editions and replaces only unused definitions" do
    seed = Rails.root.join("db/seeds.rb")
    load seed
    definitions = Workflow.where(project_id: nil).order(:name)
    assert_equal [ "KOS Brief v4", "KOS Execution v4", "KOS Fix v4" ], definitions.pluck(:name)
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
    brief = Workflow.find_by!(name: "KOS Brief v4", project_id: nil)
    Task.create!(project: Project.create!(repository: "github.com/workflow/seed", name: "Seed"),
      workflow: brief, title: "Keep existing route", description: "Do not replace this workflow", kind: "feature")
    obsolete = Workflow.create!(name: "KOS Fix v2", steps: Workflow.find_by!(name: "KOS Fix v4").steps)
    brief.update_columns(steps: [ { "name" => "Legacy" } ])

    error = assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb") }
    assert_includes error.message, "in use"
    assert_equal [ { "name" => "Legacy" } ], brief.reload.steps
    assert_equal brief.id, Task.last.workflow_id
    assert Workflow.exists?(obsolete.id)
  end

  test "seed retains used prior editions and removes unused ones without changing task steps" do
    old_brief = Workflow.create!(name: "KOS Brief v2", steps: JSON.parse(Rails.root.join("config/workflows/brief.json").read).fetch("steps"))
    old_execution = Workflow.create!(name: "KOS Execution v2", steps: JSON.parse(Rails.root.join("config/workflows/execution.json").read).fetch("steps"))
    old_fix = Workflow.create!(name: "KOS Fix v2", steps: JSON.parse(Rails.root.join("config/workflows/fix.json").read).fetch("steps"))
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
    assert Workflow.exists?(name: "KOS Brief v4", project_id: nil)
    assert Workflow.exists?(name: "KOS Execution v4", project_id: nil)
    assert Workflow.exists?(name: "KOS Fix v4", project_id: nil)
  end

  test "seed preserves used v1 and v2 and removes unused prior editions" do
    old = %w[Brief Execution Fix].flat_map do |kind|
      %w[v1 v2].map do |edition|
        Workflow.create!(name: "KOS #{kind} #{edition}", steps: JSON.parse(Rails.root.join("config/workflows/#{kind.downcase}.json").read).fetch("steps"))
      end
    end
    project = Project.create!(repository: "github.com/workflow/editions", name: "Editions")
    tasks = [ old[0], old[3] ].map do |workflow|
      Task.create!(project: project, workflow: workflow, title: workflow.name, description: "Keep assigned version", kind: "feature")
    end
    original_steps = tasks.map { |task| task.workflow.steps }

    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal [ "KOS Brief v1", "KOS Execution v2" ], tasks.map { |task| task.reload.workflow.name }
    assert_equal original_steps, tasks.map { |task| task.workflow.reload.steps }
    assert_equal [ "KOS Brief v1", "KOS Brief v4", "KOS Execution v2", "KOS Execution v4", "KOS Fix v4" ], Workflow.where(project_id: nil).order(:name).pluck(:name)
  end

  test "seed preserves assigned v3 while installing v4 and removes only unused v3" do
    brief_v3 = Workflow.find_or_create_by!(name: "KOS Brief v3", project_id: nil) { |workflow| workflow.steps = JSON.parse(Rails.root.join("config/workflows/brief-v3.json").read).fetch("steps") }
    execution_v3 = Workflow.find_or_create_by!(name: "KOS Execution v3", project_id: nil) { |workflow| workflow.steps = JSON.parse(Rails.root.join("config/workflows/execution-v3.json").read).fetch("steps") }
    fix_v3 = Workflow.find_or_create_by!(name: "KOS Fix v3", project_id: nil) { |workflow| workflow.steps = JSON.parse(Rails.root.join("config/workflows/fix-v3.json").read).fetch("steps") }
    task = Task.create!(project: Project.create!(repository: "github.com/workflow/v3", name: "V3"),
      workflow: execution_v3, title: "In progress", description: "Keep old instructions", kind: "feature")
    task.update_columns(current_step: 2)
    artifact = TaskArtifact.create!(task: task, key: "test_report", content: "# Existing checks")
    original_steps = execution_v3.steps.deep_dup

    2.times { load Rails.root.join("db/seeds.rb") }

    assert_equal execution_v3.id, task.reload.workflow_id
    assert_equal 2, task.current_step
    assert_equal original_steps, execution_v3.reload.steps
    assert_equal "# Existing checks", artifact.reload.content
    assert_not Workflow.exists?(brief_v3.id)
    assert_not Workflow.exists?(fix_v3.id)
    assert_equal [ "KOS Brief v4", "KOS Execution v3", "KOS Execution v4", "KOS Fix v4" ],
      Workflow.where(project_id: nil).order(:name).pluck(:name)
  end
end
