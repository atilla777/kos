require "digest"

class BriefPlan < ApplicationRecord
  class PlanError < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  belongs_to :brief_task, class_name: "Task"

  def self.create_for!(brief:, claim_id:, expected_step:, key:, entries:)
    normalized = validate_entries!(entries)
    raise ActionController::BadRequest unless key.is_a?(String) && key.present? && key.length <= 128

    digest = Digest::SHA256.hexdigest(JSON.generate(normalized))
    transaction do
      Task.send(:lock_project!, brief.project)
      brief.reload.lock!
      brief.send(:ensure_active_claim!, claim_id, Time.current)
      raise Task::ClaimError, "step_conflict" unless brief.current_step == expected_step
      raise PlanError, "not_brief" unless brief.workflow.name.match?(/\AKOS Brief v[1234]\z/)

      existing = find_by(brief_task_id: brief.id)
      if existing
        raise PlanError, "plan_conflict" unless existing.request_key == key && existing.request_digest == digest

        next [ existing, false ]
      end

      created = normalized.to_h do |entry|
        task = brief.project.tasks.create!(entry.slice("kind", "title", "description", "workflow_id", "task_group_id"))
        [ entry.fetch("name"), task ]
      end
      normalized.each do |entry|
        blockers = [ brief.id ] + entry.fetch("blocked_by").map { |name| created.fetch(name).id }
        created.fetch(entry.fetch("name")).replace_blockers!(blockers)
      end

      result = normalized.to_h do |entry|
        task = created.fetch(entry.fetch("name"))
        [ entry.fetch("name"), { "id" => task.id, "blocked_by_ids" => task.task_dependencies.order(:blocking_task_id).pluck(:blocking_task_id) } ]
      end
      [ create!(brief_task: brief, request_key: key, request_digest: digest, result: result), true ]
    end
  end

  def self.validate_entries!(entries)
    raise ActionController::BadRequest unless entries.is_a?(Array) && entries.any?

    normalized = entries.map do |entry|
      entry = entry.to_unsafe_h if entry.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest unless entry.is_a?(Hash)
      entry = entry.stringify_keys
      allowed = %w[name kind title description workflow_id task_group_id blocked_by]
      raise ActionController::BadRequest unless (entry.keys - allowed).empty?
      name = entry["name"]
      raise ActionController::BadRequest unless name.is_a?(String) && name.match?(/\A[a-z][a-z0-9_-]{0,79}\z/)
      %w[kind title description].each do |field|
        raise ActionController::BadRequest unless entry[field].is_a?(String) && entry[field].strip.present?
      end
      %w[workflow_id task_group_id].each do |field|
        next if field == "task_group_id" && (!entry.key?(field) || entry[field].nil?)
        raise ActionController::BadRequest unless entry[field].is_a?(Integer) && entry[field].positive?
      end
      blockers = entry.fetch("blocked_by", [])
      raise ActionController::BadRequest unless blockers.is_a?(Array) && blockers.all? { |value| value.is_a?(String) } && blockers.uniq == blockers

      allowed.filter_map { |field| [ field, entry[field] ] if entry.key?(field) }.to_h.merge("blocked_by" => blockers)
    end
    names = normalized.map { |entry| entry.fetch("name") }
    raise ActionController::BadRequest unless names.uniq == names
    raise ActionController::BadRequest unless normalized.all? { |entry| (entry.fetch("blocked_by") - names).empty? }

    normalized
  end

  private_class_method :validate_entries!
end
