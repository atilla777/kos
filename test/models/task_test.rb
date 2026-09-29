require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
  end

  test "requires kind title and description" do
    task = @project.tasks.build(workflow: workflow_for(@project))

    assert_not task.valid?
    assert task.errors.of_kind?(:kind, :blank)
    assert task.errors.of_kind?(:title, :blank)
    assert task.errors.of_kind?(:description, :blank)
  end

  test "new tasks are planned without ownership even when protected values are supplied" do
    task = @project.tasks.create!(
      workflow: workflow_for(@project),
      kind: "feature",
      title: "Task CRUD",
      description: "Implement task CRUD.",
      status: "done",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now
    )

    assert_equal "planned", task.status
    assert_nil task.session_id
    assert_nil task.claim_id
    assert_nil task.claimed_at
    assert_nil task.lease_expires_at
  end

  test "database enforces the project foreign key and task constraints" do
    attributes = {
      project_id: @project.id,
      workflow_id: workflow_for(@project).id,
      kind: "feature",
      title: "Task CRUD",
      description: "Implement task CRUD.",
      status: "invalid",
      created_at: Time.current,
      updated_at: Time.current
    }

    assert_raises(ActiveRecord::StatementInvalid) { Task.insert_all!([ attributes ]) }
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Task.insert_all!([ attributes.merge(project_id: 999_999, status: "planned") ])
    end

    assert_raises(ActiveRecord::StatementInvalid) do
      Task.insert_all!([ attributes.merge(status: "planned", session_id: "session") ])
    end

    ownership = attributes.merge(
      status: "in_progress",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now
    )
    assert_raises(ActiveRecord::StatementInvalid) do
      Task.insert_all!([ ownership.merge(session_id: " ") ])
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Task.insert_all!([ ownership.merge(claim_id: " ") ])
    end
    assert_raises(ActiveRecord::StatementInvalid) do
      Task.insert_all!([ ownership.merge(lease_expires_at: ownership.fetch(:claimed_at)) ])
    end
  end

  test "project deletion is restricted while tasks exist" do
    @project.tasks.create!(workflow: workflow_for(@project), kind: "feature", title: "Task CRUD", description: "Implement it.")

    assert_not @project.destroy
    assert Project.exists?(@project.id)
    assert_raises(ActiveRecord::InvalidForeignKey) do
      Project.where(id: @project.id).delete_all
    end
  end

  test "database enforces dependency identity uniqueness and project" do
    task = @project.tasks.create!(workflow: workflow_for(@project), kind: "feature", title: "Task", description: "Task.")
    blocker = @project.tasks.create!(workflow: workflow_for(@project), kind: "feature", title: "Blocker", description: "Blocker.")
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    foreign = other.tasks.create!(workflow: workflow_for(other), kind: "feature", title: "Foreign", description: "Foreign.")
    attributes = {
      task_id: task.id,
      blocking_task_id: blocker.id,
      project_id: @project.id,
      created_at: Time.current,
      updated_at: Time.current
    }

    TaskDependency.insert_all!([ attributes ])
    assert_raises(ActiveRecord::RecordNotUnique) { TaskDependency.insert_all!([ attributes ]) }
    assert_raises(ActiveRecord::StatementInvalid) do
      TaskDependency.insert_all!([ attributes.merge(task_id: blocker.id, blocking_task_id: blocker.id) ])
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      TaskDependency.insert_all!([ attributes.merge(blocking_task_id: foreign.id) ])
    end
  end
end
