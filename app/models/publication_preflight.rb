class PublicationPreflight < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[prepared unknown reconciled consumed].freeze
  ACTIVE_STATES = %w[prepared unknown reconciled].freeze
  UNRESOLVED_STATES = %w[prepared unknown].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :prepared_attempt, class_name: "WorkflowAttempt"
  belongs_to :current_owner_attempt, class_name: "WorkflowAttempt"
  belongs_to :observation_owner_attempt, class_name: "WorkflowAttempt", optional: true
  belongs_to :publication, optional: true

  validates :candidate_sha, :remote, :base_ref, :prepared_at, presence: true
  validates :state, inclusion: { in: STATES }

  scope :active, -> { where(state: ACTIVE_STATES) }
  scope :unresolved, -> { where(state: UNRESOLVED_STATES) }

  def error=(value)
    super(value.nil? || value.is_a?(String) ? value : JSON.generate(value))
  end

  def error
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
