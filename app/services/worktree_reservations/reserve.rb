module WorktreeReservations
  class Reserve < Base
    def self.call(repository:, task_number:, branch:, path:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      validate_path!(path)
      Task.transaction do
        task = task_for_number!(repository, task_number, lock: true)
        check_lock!(task, expected_lock_version)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        expected_branch = "kos/task-#{task.number}"
        unless branch == expected_branch && task.workflow_state.worktree_policy == "required"
          raise OperationError.new("invalid_transition", "Worktree reservation does not match the task")
        end

        existing = task.worktree_reservation
        return existing if existing && existing.state != "released" && existing.branch == branch && existing.path == path &&
          existing.workflow_attempt_id == attempt.id && existing.fencing_token == fencing_token
        raise OperationError.new("invalid_transition", "Task already has another worktree reservation") if existing

        reservation = task.worktree_reservations.create!(repository:, workflow_attempt: attempt, branch:, path:,
          fencing_token:)
        task.update!(worktree_reservation: reservation)
        reservation
      end
    rescue ActiveRecord::RecordNotUnique
      raise OperationError.new("invalid_transition", "Worktree branch or path is already reserved")
    end
  end
end
