require "test_helper"

class BuiltInCatalogTest < ActiveSupport::TestCase
  EXPECTED_STEPS = {
    "brief" => %w[brief review publish],
    "development" => %w[plan implement document review publish],
    "fix" => %w[diagnose plan implement document review publish]
  }.freeze

  EXPECTED_TIERS = {
    "brief" => %w[advanced advanced standard],
    "development" => %w[advanced standard standard advanced standard],
    "fix" => %w[advanced advanced standard standard advanced standard]
  }.freeze

  test "installs the complete canonical catalog" do
    assert_difference [ -> { TaskType.count }, -> { Workflow.count } ], 3 do
      BuiltInCatalog.install!
    end

    BuiltInCatalog.definitions.each do |key, definition|
      task_type = TaskType.find_by!(key:)
      steps = definition.fetch("steps")

      assert_equal definition, task_type.workflow.definition_json
      assert_equal EXPECTED_STEPS.fetch(key), steps.pluck("id")
      assert_equal EXPECTED_TIERS.fetch(key), steps.pluck("model_tier")
      assert steps.all? { |step| step.dig("outcomes", "needs_human") == { "pause" => "needs_human" } }
      assert steps.all? { |step| step.dig("outcomes", "blocked") == { "pause" => "blocked" } }
      refute_includes steps.pluck("id"), "check"
      assert task_type.workflow.valid?
    end
  end

  test "reruns without duplicates" do
    BuiltInCatalog.install!
    ids = TaskType.where(key: TaskType::RESERVED_KEYS).order(:key).pluck(:id, :workflow_id)

    assert_no_difference [ -> { TaskType.count }, -> { Workflow.count } ] do
      BuiltInCatalog.install!
    end

    assert_equal ids, TaskType.where(key: TaskType::RESERVED_KEYS).order(:key).pluck(:id, :workflow_id)
  end

  test "brief publication leaves child materialization to the orchestrator" do
    publish = BuiltInCatalog.definitions.fetch("brief").fetch("steps").find { |step| step.fetch("id") == "publish" }

    assert_includes publish.fetch("instruction"), "after remote verification the orchestrator materializes"
    assert_equal({ "complete_task" => true }, publish.dig("outcomes", "published"))
    assert_equal({ "next_step" => "brief" }, publish.dig("outcomes", "base_moved"))
    assert_equal({ "next_step" => "brief" }, publish.dig("outcomes", "graph_invalid"))
  end

  test "creates a new revision and preserves existing tasks and custom catalog entries" do
    BuiltInCatalog.install!
    development = TaskType.find_by!(key: "development")
    old_workflow = development.workflow
    project = create_project
    task = TaskLifecycle.new.create!(project:, task_type: development, title: "Existing",
      description_markdown: "Description")
    custom = create_task_type(key: "custom", name: "Custom")
    changed = create_workflow(name: "Changed built-in")
    development.update!(workflow: changed)

    assert_difference -> { Workflow.count }, 1 do
      BuiltInCatalog.install!
    end

    assert_equal BuiltInCatalog.definitions.fetch("development"), development.reload.workflow.definition_json
    assert_equal old_workflow, task.reload.workflow
    assert_equal "custom", custom.reload.key
    assert_equal 1, TaskType.where(key: "development").count
  end

  test "rolls back when the built-in catalog is only partially present" do
    workflow = create_workflow
    TaskType.create_builtin!(key: "brief", name: "Brief", workflow:)

    assert_no_difference [ -> { TaskType.count }, -> { Workflow.count } ] do
      assert_raises(ActiveRecord::RecordInvalid) { BuiltInCatalog.install! }
    end
  end
end
