class RepositoryEffect < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[prepared succeeded failed unknown].freeze
  UNRESOLVED_STATES = %w[prepared unknown].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :prepared_attempt, class_name: "WorkflowAttempt"
  belongs_to :current_owner_attempt, class_name: "WorkflowAttempt"

  validates :request_digest, :prepared_at, presence: true
  validates :state, inclusion: { in: STATES }

  scope :unresolved, -> { where(state: UNRESOLVED_STATES) }

  def request=(value)
    super(value.nil? || value.is_a?(String) ? value : JSON.generate(value))
  end

  def request
    value = super
    value.present? ? JSON.parse(value) : value
  end

  def result=(value)
    super(value.nil? || value.is_a?(String) ? value : JSON.generate(value))
  end

  def result
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
