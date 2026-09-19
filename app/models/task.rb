class Task < ApplicationRecord
  belongs_to :project
  belongs_to :task_type
  belongs_to :workflow
  belongs_to :parent, class_name: "Task", optional: true, inverse_of: :children

  has_many :children, class_name: "Task", foreign_key: :parent_id, inverse_of: :parent
  has_many :task_dependencies
  has_many :blockers, through: :task_dependencies
  has_many :blocking_task_dependencies, class_name: "TaskDependency", foreign_key: :blocker_id
  has_many :blocked_tasks, through: :blocking_task_dependencies, source: :task
end
