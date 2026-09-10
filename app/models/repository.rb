class Repository < ApplicationRecord
  include HasUuidPrimaryKey

  TASK_PREFIX_FORMAT = /\A[A-Z][A-Z0-9]{1,9}\z/

  has_many :tasks, dependent: :restrict_with_exception
  has_many :workflow_attempts, dependent: :restrict_with_exception
  has_many :idempotency_records, dependent: :restrict_with_exception
  has_many :task_artifacts, dependent: :restrict_with_exception
  has_many :worktree_reservations, dependent: :restrict_with_exception

  validates :git_common_dir, :trusted_remote, :trusted_remote_url, :base_ref, presence: true
  validates :task_prefix, presence: true, format: { with: TASK_PREFIX_FORMAT }
  validates :git_common_dir, :task_prefix, uniqueness: true
  validates :next_task_sequence, inclusion: { in: 1..1_000_000 }
end
