require "test_helper"

class TaskDependencyTest < ActiveSupport::TestCase
  test "accepts multiple blockers in the same project" do
    project = create_project
    task = create_task(project:)
    first_blocker = create_task(project:)
    second_blocker = create_task(project:)

    assert TaskDependency.create!(task:, blocker: first_blocker).persisted?
    assert TaskDependency.create!(task:, blocker: second_blocker).persisted?
  end

  test "accepts an acyclic diamond" do
    project = create_project
    root = create_task(project:)
    left = create_task(project:)
    right = create_task(project:)
    leaf = create_task(project:)

    TaskDependency.create!(task: left, blocker: root)
    TaskDependency.create!(task: right, blocker: root)
    TaskDependency.create!(task: leaf, blocker: left)

    assert TaskDependency.create!(task: leaf, blocker: right).persisted?
  end

  test "rejects a blocker from another project" do
    dependency = TaskDependency.new(task: create_task, blocker: create_task)

    assert_not dependency.valid?
    assert_includes dependency.errors[:blocker], "must belong to the same project as the task"
  end

  test "rejects unsaved tasks from different unsaved projects" do
    workflow = create_workflow
    task_type = TaskType.create!(name: "Type", workflow:)
    task = Task.new(project: Project.new(name: "First", remote_url: "https://example.test/first.git",
      default_branch: "main"), task_type:, workflow:, title: "Task", description_markdown: "Description",
      current_step: "develop")
    blocker = Task.new(project: Project.new(name: "Second", remote_url: "https://example.test/second.git",
      default_branch: "main"), task_type:, workflow:, title: "Blocker", description_markdown: "Description",
      current_step: "develop")

    dependency = TaskDependency.new(task:, blocker:)

    assert_not dependency.valid?
    assert_includes dependency.errors[:blocker], "must belong to the same project as the task"
  end

  test "rejects a task blocking itself" do
    task = create_task
    dependency = TaskDependency.new(task:, blocker: task)

    assert_not dependency.valid?
    assert_includes dependency.errors[:blocker], "cannot be the task itself"
  end

  test "rejects direct and indirect dependency cycles" do
    project = create_project
    first = create_task(project:)
    second = create_task(project:)
    third = create_task(project:)
    TaskDependency.create!(task: second, blocker: first)
    TaskDependency.create!(task: third, blocker: second)

    assert_not TaskDependency.new(task: first, blocker: second).valid?
    assert_not TaskDependency.new(task: first, blocker: third).valid?
  end

  test "ignores the replaced edge when validating an update" do
    project = create_project
    first = create_task(project:)
    second = create_task(project:)
    third = create_task(project:)
    dependency = TaskDependency.create!(task: first, blocker: second)
    TaskDependency.create!(task: second, blocker: third)

    assert dependency.update(task: third, blocker: first)
  end

  test "rejects a cycle introduced by updating an edge" do
    project = create_project
    first = create_task(project:)
    second = create_task(project:)
    third = create_task(project:)
    dependency = TaskDependency.create!(task: first, blocker: second)
    TaskDependency.create!(task: third, blocker: first)

    assert_not dependency.update(task: first, blocker: third)
  end
end
