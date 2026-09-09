class WorkflowStateEffect < ApplicationRecord
  include HasUuidPrimaryKey

  EFFECTS = %w[worktree_remove commit fetch rebase push].freeze

  belongs_to :workflow_state

  validates :effect, inclusion: { in: EFFECTS }, uniqueness: { scope: :workflow_state_id }
end
