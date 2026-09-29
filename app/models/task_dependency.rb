class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :blocking_task, class_name: "Task"
  belongs_to :project

  validates :blocking_task_id, uniqueness: { scope: :task_id }
end
