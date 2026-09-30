require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "seed installs one shared edition and replaces only unused definitions" do
    seed = Rails.root.join("db/seeds.rb")
    load seed
    definitions = Workflow.where(project_id: nil).order(:name)
    assert_equal [ "KOS Brief v1", "KOS Execution v1", "KOS Fix v1" ], definitions.pluck(:name)
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
    brief = Workflow.find_by!(name: "KOS Brief v1", project_id: nil)
    Task.create!(project: Project.create!(repository: "github.com/workflow/seed", name: "Seed"),
      workflow: brief, title: "Keep existing route", description: "Do not replace this workflow", kind: "feature")
    obsolete = Workflow.create!(name: "KOS Fix v2", steps: Workflow.find_by!(name: "KOS Fix v1").steps)
    brief.update_columns(steps: [ { "name" => "Legacy" } ])

    error = assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb") }
    assert_includes error.message, "in use"
    assert_equal [ { "name" => "Legacy" } ], brief.reload.steps
    assert_equal brief.id, Task.last.workflow_id
    assert Workflow.exists?(obsolete.id)
  end

  test "seed removes unused prior v2 but refuses to remove it when in use" do
    load Rails.root.join("db/seeds.rb")
    obsolete = Workflow.create!(name: "KOS Fix v2", steps: Workflow.find_by!(name: "KOS Fix v1").steps)
    load Rails.root.join("db/seeds.rb")
    assert_not Workflow.exists?(obsolete.id)

    obsolete = Workflow.create!(name: "KOS Fix v2", steps: Workflow.find_by!(name: "KOS Fix v1").steps)
    Task.create!(project: Project.create!(repository: "github.com/workflow/old-fix", name: "Old fix"),
      workflow: obsolete, title: "Existing fix", description: "Keep task", kind: "fix")
    assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb") }
    assert Workflow.exists?(obsolete.id)
  end
end
