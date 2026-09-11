require "digest"

module WorkflowCatalog
  class CanonicalDefinition
    class << self
      def normalize(definition)
        value = deep_copy(definition)
        value.fetch("statuses").each do |status|
          status.fetch("artifact_templates").sort_by! { |template| template.fetch("id") }
          status.fetch("allowed_repository_effects").sort!
          status.fetch("required_artifacts").each { |requirement| requirement.fetch("allowed_states").sort! }
          status.fetch("required_artifacts").sort_by! { |requirement| requirement.fetch("type") }
        end
        value.fetch("statuses").sort_by! { |status| status.fetch("id") }
        value.fetch("transitions").each do |transition|
          transition.fetch("conditions").sort_by! { |condition| condition_sort_key(condition) }
        end
        value.fetch("transitions").sort_by! do |transition|
          [ transition.fetch("from"), transition.fetch("to"), canonical_json(transition.fetch("conditions")) ]
        end
        value
      end

      def from_record(record)
        states = record.workflow_states.sort_by(&:identifier)
        definition = {
          "schema_version" => "1",
          "workflow_id" => record.workflow_id,
          "task_type" => record.task_type.name,
          "version" => record.version,
          "initial_status" => states.find(&:initial?).identifier,
          "terminal_status" => states.find(&:terminal?).identifier,
          "statuses" => states.reject(&:terminal?).map { |state| status_from_record(state) },
          "transitions" => record.workflow_transitions.map { |transition| transition_from_record(transition) }
        }
        normalize(definition)
      end

      def digest(definition)
        "sha256:#{Digest::SHA256.hexdigest(canonical_json(normalize(definition)))}"
      end

      def canonical_json(value)
        CanonicalJson.generate(value)
      end

      private

      def deep_copy(value)
        JSON.parse(JSON.generate(value))
      end

      def condition_sort_key(condition)
        %w[type artifact_type state decision value].map { |key| condition[key].to_s }
      end

      def status_from_record(state)
        {
          "id" => state.identifier,
          "execution_mode" => state.execution_mode,
          "instruction" => state.instruction,
          "artifact_templates" => state.artifact_templates.map do |template|
            { "id" => template.identifier, "media_type" => template.media_type, "content" => template.content }
          end,
          "allowed_repository_effects" => state.workflow_state_effects.map(&:effect),
          "worktree" => state.worktree_policy,
          "repository_changes" => state.repository_changes_policy,
          "required_artifacts" => state.artifact_requirements.map do |requirement|
            { "type" => requirement.artifact_type, "cardinality" => requirement.cardinality,
              "subject" => requirement.subject,
              "allowed_states" => requirement.artifact_requirement_states.map(&:state) }
          end
        }
      end

      def transition_from_record(transition)
        {
          "from" => transition.from_state.identifier,
          "to" => transition.to_state.identifier,
          "conditions" => transition.workflow_transition_conditions.map do |condition|
            { "type" => condition.condition_type, "artifact_type" => condition.artifact_type,
              "state" => condition.artifact_state, "decision" => condition.decision,
              "value" => condition.value }.compact
          end
        }
      end
    end
  end
end
