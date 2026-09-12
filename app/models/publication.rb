class Publication < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[prepared reconciled superseded completed].freeze
  UNRESOLVED_STATES = %w[prepared reconciled].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :prepared_attempt, class_name: "WorkflowAttempt"
  belongs_to :current_owner_attempt, class_name: "WorkflowAttempt"
  belongs_to :observation_owner_attempt, class_name: "WorkflowAttempt", optional: true

  validates :candidate_sha, :remote, :base_ref, :expected_remote_oid, :prepared_at, presence: true
  validates :state, inclusion: { in: STATES }

  scope :unresolved, -> { where(state: UNRESOLVED_STATES) }
end
