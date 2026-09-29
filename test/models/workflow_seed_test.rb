require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "seed installs three valid shared workflows once and refuses to change their steps" do
    seed = Rails.root.join("db/seeds.rb")
    load seed
    definitions = Workflow.where(project_id: nil).order(:name)
    assert_equal [ "KOS Brief v1", "KOS Execution v1", "KOS Fix v1" ], definitions.pluck(:name)
    assert_equal [ 2, 5, 6 ], definitions.map { |workflow| workflow.steps.length }
    assert definitions.all?(&:valid?)

    ids = definitions.pluck(:id)
    load seed
    assert_equal ids, Workflow.where(project_id: nil).order(:name).pluck(:id)

    brief = definitions.first
    brief.update_columns(steps: [ { "name" => "Changed" } ])
    assert_raises(RuntimeError) { load seed }
    assert_equal 3, Workflow.where(project_id: nil).count
  end
end
