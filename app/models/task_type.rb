class TaskType < ApplicationRecord
  has_many :workflow_versions, dependent: :restrict_with_exception
  has_one :workflow_draft, dependent: :restrict_with_exception
  belongs_to :current_workflow_version, class_name: "WorkflowVersion", optional: true

  validates :name, :workflow_id, presence: true, uniqueness: true
  validates :id, :name, :workflow_id, format: { with: IDENTIFIER_FORMAT }
end
