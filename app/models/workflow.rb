class Workflow < ApplicationRecord
  belongs_to :project, optional: true
  has_many :tasks, dependent: :restrict_with_error
  belongs_to :base_workflow, class_name: "Workflow", optional: true
  has_many :project_copies, class_name: "Workflow", foreign_key: :base_workflow_id, dependent: :restrict_with_error

  validates :name, presence: true
  validates :edition, numericality: { only_integer: true, greater_than: 0 }, if: :base_workflow_id?
  validate :valid_origin
  validate :valid_steps
  before_update :reject_changes

  def step_at(position)
    steps.fetch(position)
  end

  def self.visible_to(project)
    where(project_id: [ nil, project&.id ])
  end

  private

  def valid_origin
    return if base_workflow_id.nil? && edition.nil?

    unless project_id && base_workflow_id && edition && base_workflow && base_workflow.project_id.nil? && base_workflow.base_workflow_id.nil?
      errors.add(:base_workflow, "must identify a shared base and a project edition")
    end
  end

  def reject_changes
    raise ActiveRecord::ReadOnlyError, "Workflow definitions cannot be changed; create a new workflow."
  end

  def valid_steps
    unless steps.is_a?(Array) && steps.any?
      errors.add(:steps, "must be a nonempty list")
      return
    end

    steps.each_with_index do |step, index|
      unless step.is_a?(Hash) && (step.keys - %w[name instructions executor model_tier inputs outputs templates]).empty? &&
          step["name"].is_a?(String) && step["name"].strip.present? &&
          step["instructions"].is_a?(String) && step["instructions"].strip.present? &&
          %w[main subagent].include?(step["executor"]) &&
          (step["executor"] == "main" ? !step.key?("model_tier") : %w[standard advanced].include?(step["model_tier"])) &&
          step["inputs"].is_a?(Array) && step["outputs"].is_a?(Array) &&
          step["inputs"].all? { |input| valid_input?(input) } &&
          step["outputs"].all? { |output| output.is_a?(String) && output.strip.present? } &&
          step["outputs"].uniq == step["outputs"] &&
          (!step.key?("templates") || (step["templates"].is_a?(Hash) &&
            (step["templates"].keys - step["outputs"]).empty? &&
            step["templates"].values.all? { |template| template.is_a?(String) && template.strip.present? }))
        errors.add(:steps, "has an invalid step at position #{index}")
      end
    end
  end

  def valid_input?(input)
    input.is_a?(Hash) && input.keys.sort == %w[key source] &&
      %w[task blockers].include?(input["source"]) &&
      input["key"].is_a?(String) && input["key"].strip.present?
  end
end
