class TaskDependency < ApplicationRecord
  belongs_to :task
  belongs_to :blocker, class_name: "Task"
end
