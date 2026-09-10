module Api
  module V1
    class Serializer
      class << self
        def task_type(record)
          optional({
            "schema_version" => "1",
            "id" => record.id,
            "name" => record.name,
            "workflow_id" => record.workflow_id,
            "current_workflow_version_id" => record.current_workflow_version_id,
            "lock_version" => record.lock_version
          })
        end

        def workflow_summary(record)
          {
            "schema_version" => "1",
            "id" => record.id,
            "workflow_id" => record.workflow_id,
            "task_type" => record.task_type.name,
            "version" => record.version,
            "content_digest" => record.content_digest,
            "published_at" => timestamp(record.published_at)
          }
        end

        def workflow_version(record)
          workflow_summary(record).merge("definition" => workflow_definition(record))
        end

        def workflow_draft(record)
          {
            "schema_version" => "1",
            "id" => record.id,
            "workflow_id" => record.workflow_id,
            "task_type" => record.task_type.name,
            "definition" => record.definition,
            "lock_version" => record.lock_version,
            "updated_at" => timestamp(record.updated_at)
          }
        end

        def task(record)
          reservation = record.worktree_reservation
          optional({
            "schema_version" => "1",
            "id" => record.id,
            "repository_id" => record.repository_id,
            "number" => record.number,
            "title" => record.title,
            "task_type" => record.task_type.name,
            "status" => record.status,
            "workflow_status" => record.workflow_state.identifier,
            "workflow_version_id" => record.workflow_version_id,
            "lock_version" => record.lock_version,
            "active_attempt_id" => record.active_attempt_id,
            "worktree_reservation_id" => record.worktree_reservation_id,
            "branch" => reservation&.branch,
            "worktree_path" => reservation&.path,
            "created_at" => timestamp(record.created_at),
            "updated_at" => timestamp(record.updated_at)
          })
        end

        def attempt(record)
          optional({
            "schema_version" => "1",
            "id" => record.id,
            "task_id" => record.task_id,
            "workflow_status" => record.workflow_state.identifier,
            "owner_id" => record.owner_id,
            "state" => record.state,
            "fencing_token" => record.fencing_token,
            "lease_expires_at" => optional_timestamp(record.lease_expires_at),
            "started_at" => timestamp(record.started_at),
            "heartbeat_at" => optional_timestamp(record.heartbeat_at),
            "completed_at" => optional_timestamp(record.completed_at),
            "input_context_digest" => record.input_context_digest,
            "result_manifest" => record.result_manifest
          })
        end

        def worktree(record)
          {
            "schema_version" => "1",
            "id" => record.id,
            "repository_id" => record.repository_id,
            "task_id" => record.task_id,
            "attempt_id" => record.workflow_attempt_id,
            "branch" => record.branch,
            "path" => record.path,
            "state" => record.state,
            "fencing_token" => record.fencing_token,
            "created_at" => timestamp(record.created_at)
          }
        end

        def artifact(record)
          {
            "schema_version" => "1",
            "id" => record.id,
            "task_id" => record.task_id,
            "attempt_id" => record.workflow_attempt_id,
            "created_at" => timestamp(record.created_at),
            "type" => record.artifact_type,
            "state" => record.state,
            "producer" => record.producer,
            "metadata" => record.metadata
          }
        end

        private

        def workflow_definition(record)
          states = record.workflow_states.sort_by(&:identifier)
          executable = states.reject(&:terminal?)
          {
            "schema_version" => "1",
            "workflow_id" => record.workflow_id,
            "task_type" => record.task_type.name,
            "version" => record.version,
            "initial_status" => states.find(&:initial?).identifier,
            "terminal_status" => states.find(&:terminal?).identifier,
            "statuses" => executable.map { |state| workflow_status(state) },
            "transitions" => record.workflow_transitions.sort_by do |transition|
              [ transition.from_state.identifier, transition.to_state.identifier ]
            end.map { |transition| workflow_transition(transition) }
          }
        end

        def workflow_status(state)
          {
            "id" => state.identifier,
            "execution_mode" => state.execution_mode,
            "instruction" => state.instruction,
            "artifact_templates" => state.artifact_templates.sort_by(&:identifier).map do |template|
              { "id" => template.identifier, "media_type" => template.media_type, "content" => template.content }
            end,
            "allowed_repository_effects" => state.workflow_state_effects.map(&:effect).sort,
            "worktree" => state.worktree_policy,
            "repository_changes" => state.repository_changes_policy,
            "required_artifacts" => state.artifact_requirements.sort_by(&:artifact_type).map do |requirement|
              { "type" => requirement.artifact_type, "cardinality" => requirement.cardinality,
                "subject" => requirement.subject,
                "allowed_states" => requirement.artifact_requirement_states.map(&:state).sort }
            end
          }
        end

        def workflow_transition(transition)
          {
            "from" => transition.from_state.identifier,
            "to" => transition.to_state.identifier,
            "conditions" => transition.workflow_transition_conditions.sort_by(&:position).map do |condition|
              optional({ "type" => condition.condition_type, "artifact_type" => condition.artifact_type,
                "state" => condition.artifact_state, "decision" => condition.decision, "value" => condition.value })
            end
          }
        end

        def optional(value)
          value.compact
        end

        def optional_timestamp(value)
          timestamp(value) if value
        end

        def timestamp(value)
          value.utc.iso8601
        end
      end
    end
  end
end
