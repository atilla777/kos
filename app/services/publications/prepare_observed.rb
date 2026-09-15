module Publications
  class PrepareObserved < Base
    def self.call(repository:, preflight_id:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      PublicationPreflight.transaction do
        preflight = repository.publication_preflights.find_by(id: preflight_id)
        unless preflight
          raise OperationError.new("publication_preflight_not_found", "Publication preflight not found")
        end
        task = repository.tasks.lock.find(preflight.task_id)
        preflight = repository.publication_preflights.lock.find(preflight.id)
        check_lock!(task, expected_lock_version)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        validate_preflight!(repository, task, attempt, preflight)
        PublicationPreflights::Base.validate_intent!(repository, task, attempt,
          preflight.candidate_sha, preflight.remote, preflight.base_ref)
        if task.publications.where(state: "superseded", candidate_sha: preflight.candidate_sha).exists?
          raise OperationError.new("invalid_transition", "Publication candidate generation was superseded")
        end
        if task.publications.unresolved.exists? || task.active_publication_id
          raise OperationError.new("invalid_transition", "Task already has an unresolved publication")
        end

        publication = task.publications.create!(repository:, prepared_attempt: attempt,
          current_owner_attempt: attempt, candidate_sha: preflight.candidate_sha, remote: preflight.remote,
          base_ref: preflight.base_ref, expected_remote_oid: preflight.observed_remote_oid, prepared_at: now)
        task.update!(active_publication: publication)
        preflight.update!(state: "consumed", publication:, consumed_at: now)
        publication
      end
    rescue ActiveRecord::RecordNotUnique
      raise OperationError.new("invalid_transition", "Task already has an unresolved publication")
    end

    def self.validate_preflight!(repository, task, attempt, preflight)
      valid = preflight.task_id == task.id && preflight.repository_id == repository.id &&
        preflight.state == "reconciled" && preflight.publication_id.nil? &&
        preflight.current_owner_attempt_id == attempt.id && preflight.observed_remote_oid.present? &&
        preflight.remote == repository.trusted_remote && preflight.base_ref == repository.base_ref
      raise OperationError.new("invalid_transition", "Publication preflight is not current") unless valid
    end
    private_class_method :validate_preflight!
  end
end
