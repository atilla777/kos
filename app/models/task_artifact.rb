class TaskArtifact < ApplicationRecord
  include HasUuidPrimaryKey

  TYPES = %w[document candidate test review publication].freeze
  STATES = %w[produced passed failed approved changes_requested published].freeze

  belongs_to :repository
  belongs_to :task
  belongs_to :workflow_attempt

  validates :artifact_type, :state, :producer, :metadata, presence: true
  validates :artifact_type, inclusion: { in: TYPES }
  validates :state, inclusion: { in: STATES }
  validates :producer, format: { with: IDENTIFIER_FORMAT }

  def metadata=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def metadata
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
