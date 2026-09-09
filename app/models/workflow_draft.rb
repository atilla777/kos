class WorkflowDraft < ApplicationRecord
  include HasUuidPrimaryKey

  belongs_to :task_type

  validates :workflow_id, presence: true, uniqueness: true
  validates :workflow_id, format: { with: IDENTIFIER_FORMAT }
  validates :definition, presence: true

  def definition=(value)
    super(value.is_a?(String) ? value : JSON.generate(value))
  end

  def definition
    value = super
    value.present? ? JSON.parse(value) : value
  end
end
