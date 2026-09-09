class WorkflowVersion < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :task_type
  has_many :workflow_states, dependent: :restrict_with_exception
  has_many :workflow_transitions, dependent: :restrict_with_exception
  has_many :tasks, dependent: :restrict_with_exception

  validates :workflow_id, :version, :content_digest, presence: true
  validates :workflow_id, format: { with: IDENTIFIER_FORMAT }
  validates :content_digest, format: { with: /\Asha256:[0-9a-f]{64}\z/ }
  validates :version, uniqueness: { scope: :workflow_id }
end
