class TaskType < ApplicationRecord
  belongs_to :workflow

  has_many :tasks
end
