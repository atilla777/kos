module WorkflowAttempts
  class Claim < Base
    def self.call(repository:, task_number:, owner_id:, lease_seconds:, expected_lock_version:,
      idempotency_key:, now: Time.current)
      Task.transaction do
        task = task_for_number!(repository, task_number, lock: true)
        check_lock!(task, expected_lock_version)
        if task.workflow_state.terminal? || task.workflow_attempts.where(state: "started").exists?
          raise OperationError.new("invalid_transition", "Current workflow step cannot be claimed")
        end

        token = task.workflow_attempts.maximum(:fencing_token).to_i + 1
        attempt = task.workflow_attempts.create!(repository:, workflow_state: task.workflow_state,
          owner_id:, idempotency_key:, fencing_token: token, started_at: now, heartbeat_at: now,
          lease_expires_at: now + lease_seconds.seconds)
        task.update!(active_attempt: attempt)
        reservation = task.worktree_reservation
        if reservation && reservation.state != "released"
          reservation.update!(workflow_attempt: attempt, fencing_token: token)
        end
        attempt
      end
    end
  end
end
