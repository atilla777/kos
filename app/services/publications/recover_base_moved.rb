module Publications
  class RecoverBaseMoved < Base
    Result = Data.define(:task, :attempt, :publication, :transition, :recovered_at)

    def self.call(repository:, publication_id:, attempt_id:, fencing_token:, expected_lock_version:,
      now: Time.current)
      Publication.transaction do
        publication, task = publication_and_locked_task!(repository, publication_id)
        check_lock!(task, expected_lock_version)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        validate_recovery!(task, attempt, publication)
        transition = recovery_transition(task)
        raise OperationError.new("invalid_transition", "Pinned workflow does not allow base recovery") unless transition

        manifest = {
          "schema_version" => "1",
          "attempt_id" => attempt.id,
          "input_context_digest" => attempt.input_context_digest,
          "outcome" => "succeeded",
          "artifacts" => [],
          "summary" => "Durable base movement routed the task to base synchronization."
        }
        check_no_unresolved_effects!(attempt)
        task.update!(active_attempt: nil, workflow_state: transition.to_state)
        attempt.update!(state: "succeeded", heartbeat_at: now, lease_expires_at: nil,
          completed_at: now, result_manifest: manifest, completed_transition: transition)
        Result.new(task, attempt, publication, transition, now)
      end
    end

    def self.recovery_transition(task)
      transition = WorkflowTransition.includes(:to_state, :workflow_transition_conditions)
        .find_by(workflow_version_id: task.workflow_version_id, from_state_id: task.workflow_state_id,
          to_state: { identifier: "base-synchronization" })
      return unless transition

      conditions = transition.workflow_transition_conditions.map do |condition|
        [ condition.condition_type, condition.artifact_type, condition.decision, condition.value ]
      end
      expected = [
        [ "not-applicable", "publication", nil, nil ],
        [ "decision", nil, "publication-outcome", "base-moved" ]
      ]
      transition if conditions.sort_by { _1.map(&:to_s) } == expected.sort_by { _1.map(&:to_s) }
    end

    def self.validate_recovery!(task, attempt, publication)
      candidate = WorkflowSteps::CurrentCandidate.call(task)
      context = attempt.input_context
      moved = publication.state == "superseded" && publication.candidate_reachable == false &&
        publication.observed_remote_tip.present? &&
        publication.observed_remote_tip != publication.expected_remote_oid
      valid = moved && task.active_publication_id.nil? && task.workflow_state.identifier == "publication" &&
        attempt.workflow_state_id == task.workflow_state_id && candidate&.metadata&.fetch("candidate_sha") ==
          publication.candidate_sha && context.present? && attempt.input_context_digest.present? &&
        context["input_context_digest"] == attempt.input_context_digest &&
        context["workflow_status"] == "publication" && context["candidate_sha"] == publication.candidate_sha &&
        context.dig("publication", "publication_id") == publication.id
      return if valid

      raise OperationError.new("invalid_transition", "Publication is not recoverable from base movement")
    end
    private_class_method :validate_recovery!
  end
end
