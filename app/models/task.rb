class Task < ApplicationRecord
  include HasUuidPrimaryKey

  TASK_INPUT_SCHEMA_VERSION = "1"
  MAX_APPROVED_BRIEF_BYTES = 128 * 1024

  belongs_to :repository
  belongs_to :task_type
  belongs_to :workflow_version
  belongs_to :workflow_state
  belongs_to :active_attempt, class_name: "WorkflowAttempt", optional: true
  belongs_to :worktree_reservation, optional: true
  belongs_to :active_publication, class_name: "Publication", optional: true

  has_many :workflow_attempts, dependent: :restrict_with_exception
  has_many :task_artifacts, dependent: :restrict_with_exception
  has_many :worktree_reservations, dependent: :restrict_with_exception
  has_many :repository_effects, dependent: :restrict_with_exception
  has_many :publications, dependent: :restrict_with_exception
  has_many :publication_preflights, dependent: :restrict_with_exception
  has_many :publication_results, dependent: :restrict_with_exception

  validates :sequence, inclusion: { in: 1..999_999 }, uniqueness: { scope: :repository_id }
  validate :validate_title
  validate :validate_approved_task_input, on: :create

  def task_input
    return unless has_attribute?(:task_input_schema_version) && task_input_schema_version && approved_brief

    {
      "schema_version" => task_input_schema_version,
      "title" => title,
      "approved_brief" => approved_brief
    }
  end

  def number
    "#{repository.task_prefix}-#{sequence.to_s.rjust(6, "0")}"
  end

  def status
    return workflow_state.identifier == "completed" ? "completed" : "cancelled" if workflow_state.terminal?
    return "active" if active_attempt&.state == "started"

    latest_state = workflow_attempts.where(workflow_state_id:).order(fencing_token: :desc).pick(:state)
    latest_state == "needs_human" ? "blocked" : "open"
  end

  private

  def validate_title
    if title && (title.encoding != Encoding::UTF_8 || !title.valid_encoding?)
      errors.add(:title, "must be valid UTF-8")
    elsif title.blank?
      errors.add(:title, "must contain non-whitespace content")
    end
  end

  def validate_approved_task_input
    return unless has_attribute?(:task_input_schema_version)

    errors.add(:task_input_schema_version, "is not supported") unless task_input_schema_version == TASK_INPUT_SCHEMA_VERSION
    if approved_brief && (approved_brief.encoding != Encoding::UTF_8 || !approved_brief.valid_encoding?)
      errors.add(:approved_brief, "must be valid UTF-8")
    elsif approved_brief.blank?
      errors.add(:approved_brief, "must contain non-whitespace content")
    elsif approved_brief.bytesize > MAX_APPROVED_BRIEF_BYTES
      errors.add(:approved_brief, "is too large")
    end
  end
end
