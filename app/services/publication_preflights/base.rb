module PublicationPreflights
  class Base < WorkflowAttempts::Base
    MAX_OBSERVATION_CLOCK_SKEW = 5.minutes

    class << self
      private

      def preflight_and_locked_task!(repository, preflight_id)
        preflight = repository.publication_preflights.find_by(id: preflight_id)
        raise OperationError.new("publication_preflight_not_found", "Publication preflight not found") unless preflight

        task = repository.tasks.lock.find(preflight.task_id)
        [ repository.publication_preflights.lock.find(preflight.id), task ]
      end

      def owning_attempt!(repository, preflight, task, attempt_id, fencing_token, now)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        unless preflight.current_owner_attempt_id == attempt.id
          raise OperationError.new("fencing_token_stale", "Publication preflight ownership is stale")
        end
        attempt
      end

      public

      def validate_intent!(repository, task, attempt, candidate_sha, remote, base_ref)
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

      private
    end
  end
end
