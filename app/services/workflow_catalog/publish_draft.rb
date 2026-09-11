module WorkflowCatalog
  class PublishDraft
    def self.call(workflow_id:, expected_lock_version:)
      WorkflowVersion.transaction { publish(workflow_id, expected_lock_version) }
    end

    def self.publish(workflow_id, expected_lock_version)
      draft = WorkflowDraft.lock.includes(:task_type).find_by(workflow_id: workflow_id)
      raise Error.new("workflow_draft_not_found", "Workflow draft not found") unless draft
      raise Error.new("stale_lock_version", "Workflow draft lock version is stale") unless
        draft.lock_version == expected_lock_version

      errors = DefinitionValidator.new(draft.definition, task_type: draft.task_type).errors
      raise Error.new("workflow_definition_invalid", "Workflow definition is invalid", details: errors) if errors.any?

      definition = CanonicalDefinition.normalize(draft.definition)
      digest = CanonicalDefinition.digest(definition)
      existing = WorkflowVersion.find_by(workflow_id: workflow_id, version: definition.fetch("version"))
      if existing
        return existing if existing.published_at && existing.content_digest == digest

        raise Error.new("workflow_version_conflict", "Workflow semantic version is already in use")
      end

      create_version(draft.task_type, definition, digest)
    end
    private_class_method :publish

    def self.create_version(task_type, definition, digest)
      version = WorkflowVersion.create!(task_type: task_type, workflow_id: definition.fetch("workflow_id"),
        version: definition.fetch("version"), content_digest: digest)
      states = definition.fetch("statuses").to_h do |status|
        state = create_state(version, status, initial: status.fetch("id") == definition.fetch("initial_status"))
        [ status.fetch("id"), state ]
      end
      terminal = version.workflow_states.create!(identifier: definition.fetch("terminal_status"), terminal: true)
      states[terminal.identifier] = terminal
      definition.fetch("transitions").each { |transition| create_transition(version, states, transition) }
      version.update!(published_at: Time.current)
      version
    end
    private_class_method :create_version

    def self.create_state(version, status, initial:)
      state = version.workflow_states.create!(identifier: status.fetch("id"), initial: initial,
        execution_mode: status.fetch("execution_mode"), instruction: status.fetch("instruction"),
        worktree_policy: status.fetch("worktree"), repository_changes_policy: status.fetch("repository_changes"))
      status.fetch("artifact_templates").each do |template|
        state.artifact_templates.create!(identifier: template.fetch("id"), media_type: template.fetch("media_type"),
          content: template.fetch("content"))
      end
      status.fetch("allowed_repository_effects").each { |effect| state.workflow_state_effects.create!(effect: effect) }
      status.fetch("required_artifacts").each do |item|
        requirement = state.artifact_requirements.create!(artifact_type: item.fetch("type"),
          cardinality: item.fetch("cardinality"), subject: item.fetch("subject"))
        item.fetch("allowed_states").each { |value| requirement.artifact_requirement_states.create!(state: value) }
      end
      state
    end
    private_class_method :create_state

    def self.create_transition(version, states, definition)
      transition = version.workflow_transitions.create!(from_state: states.fetch(definition.fetch("from")),
        to_state: states.fetch(definition.fetch("to")))
      definition.fetch("conditions").each_with_index do |condition, position|
        transition.workflow_transition_conditions.create!(position: position,
          condition_type: condition.fetch("type"), artifact_type: condition["artifact_type"],
          artifact_state: condition["state"], decision: condition["decision"], value: condition["value"])
      end
    end
    private_class_method :create_transition
  end
end
