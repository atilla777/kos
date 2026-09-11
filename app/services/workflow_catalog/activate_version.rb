module WorkflowCatalog
  class ActivateVersion
    def self.call(task_type_id:, workflow_version_id:, expected_lock_version:)
      TaskType.transaction do
        task_type = TaskType.lock.find_by(id: task_type_id)
        raise Error.new("workflow_not_found", "Workflow not found") unless task_type
        raise Error.new("stale_lock_version", "Task type lock version is stale") unless
          task_type.lock_version == expected_lock_version

        version = task_type.workflow_versions.find_by(id: workflow_version_id)
        raise Error.new("workflow_version_not_found", "Workflow version not found") unless version&.published_at

        task_type.update!(current_workflow_version: version)
        task_type
      end
    rescue ActiveRecord::StaleObjectError
      raise Error.new("stale_lock_version", "Task type lock version is stale")
    end
  end
end
