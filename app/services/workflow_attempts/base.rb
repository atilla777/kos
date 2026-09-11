module WorkflowAttempts
  class Base
    private

    def self.task_for_number!(repository, task_number, lock: false)
      sequence = task_number.delete_prefix("#{repository.task_prefix}-").to_i
      relation = lock ? repository.tasks.lock : repository.tasks
      task = relation.find_by(sequence:)
      return task if task&.number == task_number

      raise OperationError.new("task_not_found", "Task not found")
    end

    def self.attempt_and_locked_task!(repository, attempt_id)
      attempt = repository.workflow_attempts.find_by(id: attempt_id)
      raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

      task = repository.tasks.lock.find(attempt.task_id)
      [ repository.workflow_attempts.lock.find(attempt.id), task ]
    end

    def self.check_lock!(task, expected_lock_version)
      return if task.lock_version == expected_lock_version

      raise OperationError.new("stale_lock_version", "Task lock version is stale",
        details: { "expected" => task.lock_version, "actual" => expected_lock_version })
    end

    def self.check_lease!(attempt, task, fencing_token, now)
      unless attempt.fencing_token == fencing_token && task.active_attempt_id == attempt.id
        raise OperationError.new("fencing_token_stale", "Attempt fencing token is stale")
      end
      return if attempt.state == "started" && attempt.lease_expires_at > now

      raise OperationError.new("lease_expired", "Attempt lease has expired")
    end

    def self.check_context!(attempt, manifest)
      valid = attempt.input_context.present? && attempt.input_context_digest.present? &&
        manifest["attempt_id"] == attempt.id &&
        manifest["input_context_digest"] == attempt.input_context_digest
      return if valid

      raise OperationError.new("context_unavailable", "Attempt context is unavailable")
    end
  end
end
