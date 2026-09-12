class WorkflowAttempt < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[started succeeded failed interrupted needs_human].freeze
  RECONCILIATION_STATES = %w[
    no_effect worktree_materialized repository_effect_pending publication_unknown
  ].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :workflow_state
  belongs_to :completed_transition, class_name: "WorkflowTransition", optional: true

  has_many :task_artifacts, dependent: :restrict_with_exception
  has_many :worktree_reservations, dependent: :restrict_with_exception
  has_many :prepared_repository_effects, class_name: "RepositoryEffect", foreign_key: :prepared_attempt_id,
    inverse_of: :prepared_attempt, dependent: :restrict_with_exception
  has_many :owned_repository_effects, class_name: "RepositoryEffect", foreign_key: :current_owner_attempt_id,
    inverse_of: :current_owner_attempt, dependent: :restrict_with_exception

  validates :owner_id, :idempotency_key, :started_at, presence: true
  validates :owner_id, format: { with: IDENTIFIER_FORMAT }
  validates :state, inclusion: { in: STATES }
  validates :reconciliation_state, inclusion: { in: RECONCILIATION_STATES }, allow_nil: true
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
