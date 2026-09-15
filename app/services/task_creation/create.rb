module TaskCreation
  class Create
    def self.call(repository:, task_input:, task_type_name:)
      validate_task_input!(task_input)

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

        task = allocator.tasks.create!(title: task_input.fetch("title"), sequence: sequence, task_type: task_type,
          workflow_version: version, workflow_state: state,
          task_input_schema_version: task_input.fetch("schema_version"),
          approved_brief: task_input.fetch("approved_brief"))
        allocator.update!(next_task_sequence: sequence + 1)
        task
      end
    end

    def self.validate_task_input!(task_input)
      values = task_input.values_at("title", "approved_brief")
      unless values.all? { _1.encoding == Encoding::UTF_8 && _1.valid_encoding? }
        raise OperationError.new("malformed_input", "Approved task input must be valid UTF-8")
      end
      return if values.last.bytesize <= Task::MAX_APPROVED_BRIEF_BYTES

      raise OperationError.new("malformed_input", "Approved task brief is too large",
        details: { "field" => "task_input.approved_brief" })
    end
    private_class_method :validate_task_input!
  end
end
