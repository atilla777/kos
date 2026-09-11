module WorkflowCatalog
  class ImportDraft
    def self.call(workflow_id:, definition:, expected_lock_version:)
      WorkflowDraft.transaction do
        task_type = TaskType.find_by(workflow_id: workflow_id)
        raise Error.new("workflow_not_found", "Workflow not found") unless task_type

        errors = DefinitionValidator.new(definition, task_type: task_type).structural_errors
        raise Error.new("workflow_definition_invalid", "Workflow definition is invalid", details: errors) if errors.any?

        draft = WorkflowDraft.lock.find_by(workflow_id: workflow_id)
        if draft
          raise Error.new("stale_lock_version", "Workflow draft lock version is stale") unless
            draft.lock_version == expected_lock_version

          draft.update!(definition: definition)
          draft
        else
          raise Error.new("stale_lock_version", "Workflow draft lock version is stale") unless expected_lock_version.zero?

          WorkflowDraft.create!(task_type: task_type, workflow_id: workflow_id, definition: definition, lock_version: 1)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      raise Error.new("stale_lock_version", "Workflow draft lock version is stale")
    rescue ActiveRecord::StaleObjectError
      raise Error.new("stale_lock_version", "Workflow draft lock version is stale")
    end
  end
end
