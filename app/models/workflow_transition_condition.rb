class WorkflowTransitionCondition < ApplicationRecord
  include HasUuidPrimaryKey

  CONDITION_TYPES = %w[always artifact-present artifact-state decision not-applicable].freeze

  belongs_to :workflow_transition

  validates :condition_type, inclusion: { in: CONDITION_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_transition_id }
  validates :decision, :value, format: { with: IDENTIFIER_FORMAT }, allow_nil: true
end
