require "test_helper"

class BuiltInCatalogTest < ActiveSupport::TestCase
  EXPECTED_STEPS = {
    "brief" => %w[brief review publish verify],
    "development" => %w[plan implement document review publish verify],
    "fix" => %w[diagnose plan implement document review publish verify]
  }.freeze

  EXPECTED_TIERS = {
    "brief" => %w[advanced advanced standard advanced],
    "development" => %w[advanced standard standard advanced standard advanced],
    "fix" => %w[advanced advanced standard standard advanced standard advanced]
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
      completing = steps.flat_map do |step|
        step.fetch("outcomes").filter_map { |outcome, action| [ step.fetch("id"), outcome ] if action["complete_task"] }
      end
      assert_equal [ [ "verify", "verified" ] ], completing
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

  test "brief publication and verification preserve graph correction semantics" do
    steps = BuiltInCatalog.definitions.fetch("brief").fetch("steps").index_by { |step| step.fetch("id") }
    publish = steps.fetch("publish")
    verify = steps.fetch("verify")

    assert_includes publish.fetch("instruction"), "after remote verification, materialize"
    assert_equal({ "next_step" => "verify" }, publish.dig("outcomes", "published"))
    assert_equal({ "next_step" => "review" }, publish.dig("outcomes", "review_invalid"))
    assert_equal({ "next_step" => "brief" }, publish.dig("outcomes", "base_moved"))
    assert_equal({ "next_step" => "brief" }, publish.dig("outcomes", "graph_invalid"))
    assert_equal({ "complete_task" => true }, verify.dig("outcomes", "verified"))
    assert_equal({ "next_step" => "publish" }, verify.dig("outcomes", "publication_missing"))
    assert_equal({ "next_step" => "publish" }, verify.dig("outcomes", "materialization_missing"))
    assert_equal({ "next_step" => "brief" }, verify.dig("outcomes", "brief_invalid"))
  end

  test "development and fix expose explicit predecessor correction routes" do
    %w[development fix].each do |key|
      steps = BuiltInCatalog.definitions.fetch(key).fetch("steps").index_by { |step| step.fetch("id") }

      assert_equal({ "next_step" => "plan" }, steps.dig("implement", "outcomes", "plan_invalid"))
      assert_equal({ "next_step" => "implement" }, steps.dig("document", "outcomes", "implementation_invalid"))
      assert_equal({ "next_step" => "implement" }, steps.dig("review", "outcomes", "changes_requested"))
      assert_equal({ "next_step" => "plan" }, steps.dig("review", "outcomes", "redesign_required"))
      assert_equal({ "next_step" => "review" }, steps.dig("publish", "outcomes", "review_invalid"))
      assert_equal({ "next_step" => "implement" }, steps.dig("publish", "outcomes", "base_moved"))
      assert_equal({ "next_step" => "verify" }, steps.dig("publish", "outcomes", "published"))
      assert_equal({ "complete_task" => true }, steps.dig("verify", "outcomes", "verified"))
      assert_equal({ "next_step" => "publish" }, steps.dig("verify", "outcomes", "publication_missing"))
      assert_equal({ "next_step" => "implement" }, steps.dig("verify", "outcomes", "changes_invalid"))
    end

    fix = BuiltInCatalog.definitions.fetch("fix").fetch("steps").index_by { |step| step.fetch("id") }
    assert_equal({ "next_step" => "diagnose" }, fix.dig("plan", "outcomes", "diagnosis_invalid"))
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
