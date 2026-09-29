require "test_helper"

class TaskGroupTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "KOS", repository: "github.com/atilla777/kos")
    @group = @project.task_groups.create!(kind: "epic", title: "Groups", description: "Implement groups.")
  end

  test "only epic groups with a title and description are valid" do
    group = @project.task_groups.build(kind: "initiative")

    assert_not group.valid?
    assert group.errors.of_kind?(:kind, :inclusion)
    assert group.errors.of_kind?(:title, :blank)
    assert group.errors.of_kind?(:description, :blank)
  end

  test "computes progress from current task statuses" do
    assert_equal({ completed: false, tasks_total: 0, tasks_done: 0, tasks_in_progress: 0 }, @group.progress)

    done = @project.tasks.create!(task_group: @group, kind: "feature", title: "Done", description: "Done task.")
    active = @project.tasks.create!(task_group: @group, kind: "feature", title: "Active", description: "Active task.")
    done.update!(status: "done")
    active.update!(
      status: "in_progress",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now
    )

    assert_equal({ completed: false, tasks_total: 2, tasks_done: 1, tasks_in_progress: 1 }, @group.progress)

    active.update!(status: "done", session_id: nil, claim_id: nil, claimed_at: nil, lease_expires_at: nil)
    assert_equal true, @group.progress.fetch(:completed)
  end

  test "database and model reject membership across projects" do
    other = Project.create!(name: "Other", repository: "github.com/atilla777/other")
    task = other.tasks.build(task_group: @group, kind: "feature", title: "Wrong", description: "Wrong project.")

    assert_not task.valid?
    assert_includes task.errors[:task_group], "must belong to the same project"

    task.task_group = nil
    task.save!
    assert_raises(ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid) do
      Task.where(id: task.id).update_all(task_group_id: @group.id)
    end
  end

  test "group membership can only change while a task is planned" do
    replacement = @project.task_groups.create!(kind: "epic", title: "Replacement", description: "Replacement group.")
    task = @project.tasks.create!(task_group: @group, kind: "feature", title: "Active", description: "Active task.")
    task.update!(
      status: "in_progress",
      session_id: "session",
      claim_id: "claim",
      claimed_at: Time.current,
      lease_expires_at: 1.hour.from_now
    )

    task.task_group = replacement

    assert_not task.save
    assert_includes task.errors[:task_group], "can only be changed while the task is planned"
  end

  test "nonempty groups and projects with groups cannot be deleted" do
    @project.tasks.create!(task_group: @group, kind: "feature", title: "Task", description: "Implement it.")

    assert_not @group.destroy
    assert_not @project.destroy
    assert_raises(ActiveRecord::InvalidForeignKey) { TaskGroup.where(id: @group.id).delete_all }
  end
end
