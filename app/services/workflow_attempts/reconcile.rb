module WorkflowAttempts
  class Reconcile < Base
    def self.call(repository:, attempt_id:, observed_state:, evidence_digest:, expected_lock_version:,
      now: Time.current)
      WorkflowAttempt.transaction do
        attempt, task = attempt_and_locked_task!(repository, attempt_id)
        check_lock!(task, expected_lock_version)
        if attempt.state == "interrupted"
          return reconcile_interrupted!(attempt, observed_state, evidence_digest, now)
        end

        unless attempt.state == "started" && attempt.lease_expires_at <= now &&
            task.active_attempt_id == attempt.id
          raise OperationError.new("invalid_transition", "Attempt is not available for reconciliation")
        end
        validate_effect_observation!(attempt, observed_state)

        task.update!(active_attempt: nil)
        attempt.update!(state: "interrupted", lease_expires_at: nil, completed_at: now,
          reconciliation_state: observed_state, reconciliation_evidence_digest: evidence_digest,
          reconciled_at: now)
        attempt
      end
    end

    def self.reconcile_interrupted!(attempt, observed_state, evidence_digest, now)
      unless attempt.reconciliation_state
        attempt.update!(reconciliation_state: observed_state,
          reconciliation_evidence_digest: evidence_digest, reconciled_at: now,
          legacy_reconciliation_pending: false)
        return attempt
      end
      if attempt.reconciliation_state == observed_state &&
          attempt.reconciliation_evidence_digest == evidence_digest
        return attempt
      end

      raise OperationError.new("invalid_transition", "Attempt was reconciled with different evidence")
    end
    private_class_method :reconcile_interrupted!

    def self.validate_effect_observation!(attempt, observed_state)
      if attempt.owned_repository_effects.unresolved.exists?
        return if observed_state == "repository_effect_pending"
      elsif attempt.owned_publications.unresolved.exists?
        return if observed_state == "publication_unknown"
      elsif !%w[repository_effect_pending publication_unknown].include?(observed_state)
        return
      end

      raise OperationError.new("invalid_transition", "Attempt observation does not match unresolved effects")
    end
    private_class_method :validate_effect_observation!
  end
end
