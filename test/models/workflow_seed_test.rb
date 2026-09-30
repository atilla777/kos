require "test_helper"

class WorkflowSeedTest < ActiveSupport::TestCase
  test "seed installs versioned shared workflows once without changing earlier editions" do
    seed = Rails.root.join("db/seeds.rb")
    load seed
    definitions = Workflow.where(project_id: nil).order(:name)
    assert_equal [ "KOS Brief v1", "KOS Brief v2", "KOS Execution v1", "KOS Execution v2", "KOS Fix v1", "KOS Fix v2" ], definitions.pluck(:name)
    assert_equal [ 2, 3, 5, 5, 6, 6 ], definitions.map { |workflow| workflow.steps.length }
    assert definitions.all?(&:valid?)

    ids = definitions.pluck(:id)
    load seed
    assert_equal ids, Workflow.where(project_id: nil).order(:name).pluck(:id)

    brief = definitions.first
    brief.update_columns(steps: [ { "name" => "Changed" } ])
    assert_raises(RuntimeError) { load seed }
    assert_equal 6, Workflow.where(project_id: nil).count
  end
end
