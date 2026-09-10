class WorkflowAttempt < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[started succeeded failed interrupted needs_human].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :workflow_state

  has_many :task_artifacts, dependent: :restrict_with_exception
  has_many :worktree_reservations, dependent: :restrict_with_exception

  validates :owner_id, :idempotency_key, :started_at, presence: true
  validates :owner_id, format: { with: IDENTIFIER_FORMAT }
  validates :state, inclusion: { in: STATES }
  validates :fencing_token, numericality: { only_integer: true, greater_than: 0 }

  def input_context=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def input_context
    value = super
    value.present? ? JSON.parse(value) : value
  end

  def result_manifest=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def result_manifest
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
