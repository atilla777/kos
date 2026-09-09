class Task < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :repository
  belongs_to :task_type
  belongs_to :workflow_version
  belongs_to :workflow_state

  validates :title, presence: true
  validates :sequence, inclusion: { in: 1..999_999 }, uniqueness: { scope: :repository_id }

  def number
    "#{repository.task_prefix}-#{sequence.to_s.rjust(6, "0")}"
  end
end
