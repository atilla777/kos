module WorkflowAttempts
  class Finish < Base
    def self.call(repository:, attempt_id:, fencing_token:, expected_lock_version:, manifest:, state:,
      now: Time.current)
      WorkflowAttempt.transaction do
        attempt, task = attempt_and_locked_task!(repository, attempt_id)
        check_lock!(task, expected_lock_version)
        check_lease!(attempt, task, fencing_token, now)
        check_context!(attempt, manifest)

        task.update!(active_attempt: nil)
        attempt.update!(state:, heartbeat_at: now, lease_expires_at: nil, completed_at: now,
          result_manifest: manifest)
        attempt
      end
    end
  end
end
