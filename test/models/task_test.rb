require "test_helper"

class TaskTest < ActiveSupport::TestCase
  test "accepts any step from its workflow" do
    assert create_task(current_step: "check").persisted?
  end

  test "rejects a current step outside its workflow" do
    task = create_task

    assert_not task.update(current_step: "publish")
    assert_includes task.errors[:current_step], "must identify a step in the task workflow"
  end

  test "accepts a parent from the same project" do
    project = create_project
    parent = create_task(project:)

    assert create_task(project:, parent:).persisted?
  end

  test "rejects a parent from another project" do
    task = create_task
    other_parent = create_task

    assert_not task.update(parent: other_parent)
    assert_includes task.errors[:parent], "must belong to the same project"
  end

  test "rejects a task as its own parent" do
    task = create_task

    assert_not task.update(parent: task)
    assert_includes task.errors[:parent], "cannot create a cycle"
  end

  test "rejects direct and indirect parent cycles" do
    project = create_project
    first = create_task(project:)
    second = create_task(project:, parent: first)
    third = create_task(project:, parent: second)

    assert_not first.update(parent: second)
    assert_not first.update(parent: third)
  end

  test "accepts a deep acyclic parent hierarchy" do
    project = create_project
    root = create_task(project:)
    child = create_task(project:, parent: root)

    assert create_task(project:, parent: child).persisted?
  end

  test "does not allow a task to move between projects" do
    task = create_task

    assert_not task.update(project: create_project(name: "Other"))
    assert_includes task.errors[:project], "cannot change after task creation"
  end

  test "does not allow a task to change workflow" do
    task = create_task

    assert_not task.update(workflow: create_workflow(name: "Other"))
    assert_includes task.errors[:workflow], "cannot change after task creation"
  end

  test "does not allow tasks to be destroyed" do
    task = create_task

    assert_not task.destroy
    assert task.persisted?
    assert_includes task.errors[:base], "tasks cannot be deleted; cancel the task instead"
  end
end
