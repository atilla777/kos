class ArtifactRequirement < ApplicationRecord
  include HasUuidPrimaryKey

  TYPES = %w[document candidate test review publication].freeze

  belongs_to :workflow_state
  has_many :artifact_requirement_states, dependent: :restrict_with_exception

  validates :artifact_type, inclusion: { in: TYPES }, uniqueness: { scope: :workflow_state_id }
  validates :cardinality, inclusion: { in: %w[one many] }
  validates :subject, inclusion: { in: %w[task candidate] }
end
