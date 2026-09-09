class ArtifactRequirementState < ApplicationRecord
  include HasUuidPrimaryKey

  STATES = %w[produced passed failed approved changes_requested published].freeze

  belongs_to :artifact_requirement

  validates :state, inclusion: { in: STATES }, uniqueness: { scope: :artifact_requirement_id }
end
