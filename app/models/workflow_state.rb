class WorkflowState < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :workflow_version
  has_many :artifact_templates, dependent: :restrict_with_exception
  has_many :workflow_state_effects, dependent: :restrict_with_exception
  has_many :artifact_requirements, dependent: :restrict_with_exception
  has_many :workflow_attempts, dependent: :restrict_with_exception

  validates :identifier, presence: true, uniqueness: { scope: :workflow_version_id }
  validates :identifier, format: { with: IDENTIFIER_FORMAT }
  validates :execution_mode, inclusion: { in: %w[main_session subagent] }, unless: :terminal?
  validates :worktree_policy, inclusion: { in: %w[required none] }, unless: :terminal?
  validates :repository_changes_policy, inclusion: { in: %w[allowed forbidden] }, unless: :terminal?
  validates :instruction, presence: true, unless: :terminal?
end
