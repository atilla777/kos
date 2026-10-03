require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "explicit bases match checked-in definitions and seed is repeatable" do
    2.times { load Rails.root.join("db/seeds.rb") }
    bases = Workflow.where(project_id: nil, name: %w[Brief Execution Fix].map { |kind| "KOS Base #{kind} v1" }).order(:name)
    assert_equal 3, bases.count
    assert_equal [ 3, 4, 5 ], bases.map { |workflow| workflow.steps.length }
    bases.each do |base|
      path = Rails.root.join("config/workflows/#{base.name.split[2].downcase}-base-v1.json")
      assert_equal JSON.parse(path.read).fetch("steps"), base.steps
      assert base.valid?
    end
    ids = bases.pluck(:id)
    load Rails.root.join("db/seeds.rb")
    assert_equal ids, Workflow.where(id: ids).order(:name).pluck(:id)
  end

  test "used changed base rejects seeding without partial writes" do
    load Rails.root.join("db/seeds.rb")
    base = Workflow.find_by!(project_id: nil, name: "KOS Base Brief v1")
    project = Project.create!(repository: "github.com/workflow/seed", name: "Seed")
    project.workflows.create!(name: "KOS Brief v1", steps: base.steps, base_workflow: base, edition: 1)
    base.update_columns(steps: [ { "name" => "Changed" } ])
    ids = Workflow.pluck(:id)

    assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb") }
    assert_equal ids, Workflow.pluck(:id)
    assert_equal [ { "name" => "Changed" } ], base.reload.steps
  end
end
