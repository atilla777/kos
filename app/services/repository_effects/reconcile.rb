module RepositoryEffects
  class Reconcile < Base
    def self.call(repository:, effect_id:, effect_result:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      RepositoryEffect.transaction do
        effect, task = effect_and_locked_task!(repository, effect_id)
        check_lock!(task, expected_lock_version)
        owning_attempt!(repository, effect, task, attempt_id, fencing_token, now)
        if %w[succeeded failed].include?(effect.state)
          raise OperationError.new("invalid_transition", "Repository effect is already terminal")
        end

        validate_result!(effect, effect_result, attempt_id)
        outcome = effect_result.fetch("result").fetch("outcome")
        effect.update!(state: outcome, result: JSON.parse(JSON.generate(effect_result)), reconciled_at: now)
        effect
      end
    end

    def self.validate_result!(effect, result, attempt_id)
      request = effect.request
      valid = result["effect_intent_id"] == effect.id && result["request_attempt_id"] == effect.prepared_attempt_id &&
        result["owner_attempt_id"] == attempt_id &&
        result["input_context_digest"] == request["input_context_digest"] &&
        result["effect_request_digest"] == effect.request_digest &&
        result.dig("result", "operation") == request.dig("effect", "operation")
      return if valid

      raise OperationError.new("invalid_transition", "Repository effect result does not match its intent")
    end
    private_class_method :validate_result!
  end
end
