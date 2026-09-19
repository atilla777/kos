class Workflow < ApplicationRecord
  has_many :task_types
  has_many :tasks
end
