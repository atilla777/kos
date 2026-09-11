module TaskCreation
  class Create
    def self.call(repository:, title:, task_type_name:)
      Task.transaction do
        task_type = TaskType.lock.find_by(name: task_type_name)
        version = task_type&.current_workflow_version
        state = version&.workflow_states&.find_by(initial: true)
        unless version&.published_at && state
          raise OperationError.new("task_type_unavailable", "Task type has no active published workflow")
        end

        allocator = Repository.lock.find(repository.id)
        sequence = allocator.next_task_sequence
        if sequence > 999_999
          raise OperationError.new("task_number_exhausted", "Repository task numbers are exhausted")
        end

        task = allocator.tasks.create!(title: title, sequence: sequence, task_type: task_type,
          workflow_version: version, workflow_state: state)
        allocator.update!(next_task_sequence: sequence + 1)
        task
      end
    end
  end
end
