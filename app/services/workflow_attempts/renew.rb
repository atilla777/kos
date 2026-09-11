module WorkflowAttempts
  class Renew < Base
    def self.call(repository:, attempt_id:, fencing_token:, expected_lock_version:, lease_seconds:,
      now: Time.current)
      WorkflowAttempt.transaction do
        attempt, task = attempt_and_locked_task!(repository, attempt_id)
        check_lock!(task, expected_lock_version)
        check_lease!(attempt, task, fencing_token, now)
        attempt.update!(heartbeat_at: now, lease_expires_at: now + lease_seconds.seconds)
        attempt
      end
    end
  end
end
