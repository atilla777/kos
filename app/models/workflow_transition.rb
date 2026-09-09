class WorkflowTransition < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :workflow_version
  belongs_to :from_state, class_name: "WorkflowState"
  belongs_to :to_state, class_name: "WorkflowState"
  has_many :workflow_transition_conditions, dependent: :restrict_with_exception
end
