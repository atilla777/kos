module Publications
  class Prepare < Base
    def self.call(repository:, task_number:, candidate_sha:, remote:, base_ref:, expected_remote_oid:,
      attempt_id:, fencing_token:, expected_lock_version:, now: Time.current)
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
        if task.publications.unresolved.exists? || task.active_publication_id
          raise OperationError.new("invalid_transition", "Task already has an unresolved publication")
        end

        publication = task.publications.create!(repository:, prepared_attempt: attempt,
          current_owner_attempt: attempt, candidate_sha:, remote:, base_ref:, expected_remote_oid:,
          prepared_at: now)
        task.update!(active_publication: publication)
        publication
      end
    rescue ActiveRecord::RecordNotUnique
      raise OperationError.new("invalid_transition", "Task already has an unresolved publication")
    end

    def self.validate_intent!(repository, task, attempt, candidate_sha, remote, base_ref)
      unless task.workflow_state.identifier == "publication" && attempt.workflow_state_id == task.workflow_state_id
        raise OperationError.new("invalid_transition", "Publication is not active for this task")
      end
      unless remote == repository.trusted_remote && base_ref == repository.base_ref
        raise OperationError.new("invalid_transition", "Publication target is not trusted")
      end

      candidate = WorkflowSteps::CurrentCandidate.call(task)
      unless candidate&.metadata&.fetch("candidate_sha") == candidate_sha
        raise OperationError.new("invalid_transition", "Publication candidate is not current")
      end

      review = task.task_artifacts.joins(workflow_attempt: :completed_transition)
        .where(artifact_type: "review", state: "approved", workflow_attempts: { state: "succeeded" },
          workflow_transitions: { to_state_id: task.workflow_state_id }).order(created_at: :desc).first
      metadata = review&.metadata
      valid = metadata&.fetch("candidate_sha", nil) == candidate_sha &&
        metadata&.fetch("review_attempt_id", nil) == review&.workflow_attempt_id &&
        review&.workflow_attempt_id != candidate.workflow_attempt_id
      raise OperationError.new("invalid_transition", "Candidate lacks an approved independent review") unless valid
    end
    private_class_method :validate_intent!
  end
end
