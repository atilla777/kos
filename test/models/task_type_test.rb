require "test_helper"

class TaskTypeTest < ActiveSupport::TestCase
  test "requires a unique stable key" do
    workflow = create_workflow
    create_task_type(key: "feature", workflow:)

    missing = TaskType.new(name: "Missing", workflow:)
    duplicate = TaskType.new(key: "feature", name: "Duplicate", workflow:)

    assert_not missing.valid?
    assert_includes missing.errors[:key], "can't be blank"
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "rejects reserved keys for ordinary task types" do
    TaskType::RESERVED_KEYS.each do |key|
      task_type = TaskType.new(key:, name: key.titleize, workflow: create_workflow(name: key))

      assert_not task_type.valid?
      assert_includes task_type.errors[:key], "is reserved for a built-in task type"
    end
  end

  test "keeps the key immutable" do
    task_type = create_task_type(key: "feature")

    assert_not task_type.update(key: "renamed")
    assert_equal "feature", task_type.reload.key
  end
end
