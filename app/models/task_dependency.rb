class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :blocker, class_name: "Task"

  validates :blocker_id, uniqueness: { scope: :task_id }
  validate :tasks_belong_to_same_project
  validate :task_does_not_block_itself
  validate :dependency_does_not_create_cycle
  validate :task_has_not_been_claimed

  before_destroy :prevent_change_after_claim

  private

  def tasks_belong_to_same_project
    return if task.nil? || blocker.nil? || task.project == blocker.project

    errors.add(:blocker, "must belong to the same project as the task")
  end

  def task_does_not_block_itself
    return unless task && blocker && (task.equal?(blocker) || (task.id && task.id == blocker.id))

    errors.add(:blocker, "cannot be the task itself")
  end

  def dependency_does_not_create_cycle
    return unless task_id && blocker_id

    pending = [ blocker_id ]
    visited = {}

    until pending.empty?
      current_id = pending.pop
      if current_id == task_id
        errors.add(:blocker, "cannot create a dependency cycle")
        return
      end
      next if visited[current_id]

      visited[current_id] = true
      dependencies = TaskDependency.where(task_id: current_id)
      dependencies = dependencies.where.not(id:) if id
      pending.concat(dependencies.pluck(:blocker_id))
    end
  end

  def task_has_not_been_claimed
    protected_task_ids = [ task_id ]
    protected_task_ids << task_id_in_database if persisted? && will_save_change_to_task_id?
    return unless Task.where(id: protected_task_ids.compact).where.not(status: "pending").or(
      Task.where(id: protected_task_ids.compact).where("claim_version > 0")
    ).exists?

    errors.add(:task, "dependencies can change only while the task is pending and unclaimed")
  end

  def prevent_change_after_claim
    persisted_task_id = task_id_in_database || task_id
    task = Task.find_by(id: persisted_task_id)
    return if task&.status == "pending" && task.claim_version.zero?

    errors.add(:task, "dependencies can change only while the task is pending and unclaimed")
    throw :abort
  end
end
