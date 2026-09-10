class Task < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :repository
  belongs_to :task_type
  belongs_to :workflow_version
  belongs_to :workflow_state
  belongs_to :active_attempt, class_name: "WorkflowAttempt", optional: true
  belongs_to :worktree_reservation, optional: true

  has_many :workflow_attempts, dependent: :restrict_with_exception
  has_many :task_artifacts, dependent: :restrict_with_exception
  has_many :worktree_reservations, dependent: :restrict_with_exception

  validates :title, presence: true
  validates :sequence, inclusion: { in: 1..999_999 }, uniqueness: { scope: :repository_id }

  def number
    "#{repository.task_prefix}-#{sequence.to_s.rjust(6, "0")}"
  end
end
