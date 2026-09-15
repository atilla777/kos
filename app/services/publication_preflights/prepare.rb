module PublicationPreflights
  class Prepare < Base
    def self.call(repository:, task_number:, candidate_sha:, remote:, base_ref:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      Task.transaction do
        task = task_for_number!(repository, task_number, lock: true)
        check_lock!(task, expected_lock_version)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        validate_intent!(repository, task, attempt, candidate_sha, remote, base_ref)
        if task.publications.where(state: "superseded", candidate_sha:).exists?
          raise OperationError.new("invalid_transition", "Publication candidate generation was superseded")
        end
        if task.publication_preflights.active.exists? || task.publications.unresolved.exists? || task.active_publication_id
          raise OperationError.new("invalid_transition", "Task already has an active publication operation")
        end

        task.publication_preflights.create!(repository:, prepared_attempt: attempt,
          current_owner_attempt: attempt, candidate_sha:, remote:, base_ref:, prepared_at: now)
      end
    rescue ActiveRecord::RecordNotUnique
      raise OperationError.new("invalid_transition", "Task already has an active publication preflight")
    end
  end
end
