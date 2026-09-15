require "digest"

module RepositoryEffects
  class Prepare < Base
    def self.call(repository:, task_number:, effect_request:, attempt_id:, fencing_token:,
      expected_lock_version:, now: Time.current)
      Task.transaction do
        task = task_for_number!(repository, task_number, lock: true)
        check_lock!(task, expected_lock_version)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        validate_request!(task, attempt, effect_request)
        validate_base_synchronization!(task, attempt, effect_request)
        request = JSON.parse(JSON.generate(effect_request))
        digest = "sha256:#{Digest::SHA256.hexdigest(WorkflowCatalog::CanonicalJson.generate(request))}"
        task.repository_effects.create!(repository:, prepared_attempt: attempt, current_owner_attempt: attempt,
          request:, request_digest: digest, prepared_at: now)
      end
    end

    def self.validate_request!(task, attempt, request)
      context = attempt.input_context
      unless context && attempt.input_context_digest && request["attempt_id"] == attempt.id &&
          request["input_context_digest"] == attempt.input_context_digest
        raise OperationError.new("context_unavailable", "Attempt context is unavailable")
      end

      effect = request.fetch("effect")
      operation = effect.fetch("operation")
      unless context.fetch("allowed_repository_effects", []).include?(operation)
        raise OperationError.new("invalid_transition", "Repository effect is not allowed by the context")
      end
      validate_worktree_binding!(context, effect) if %w[commit rebase].include?(operation)
      if operation == "commit" && effect["task_number"] != task.number
        raise OperationError.new("invalid_transition", "Repository effect does not match the task")
      end
    end
    private_class_method :validate_request!

    def self.validate_worktree_binding!(context, effect)
      worktree = context["worktree"]
      valid = worktree && effect["reservation_id"] == worktree["reservation_id"] &&
        effect["expected_head_sha"] == worktree["head_sha"]
      return if valid

      raise OperationError.new("invalid_transition", "Repository effect does not match the worktree context")
    end
    private_class_method :validate_worktree_binding!

    def self.validate_base_synchronization!(task, attempt, request)
      return unless task.workflow_state.identifier == "base-synchronization"

      effects = attempt.owned_repository_effects.to_a
      effect = request.fetch("effect")
      operation = effect.fetch("operation")
      valid = case operation
      when "fetch"
        effects.empty? && effect["remote"] == task.repository.trusted_remote &&
          effect["ref"] == task.repository.base_ref
      when "rebase"
        fetches = effects.select { _1.request.dig("effect", "operation") == "fetch" }
        fetch = fetches.one? ? fetches.first : nil
        effects.one? && fetch&.state == "succeeded" &&
          effect["onto_sha"] == fetch.result&.dig("result", "observed_oid")
      else
        false
      end
      return if valid

      raise OperationError.new("invalid_transition", "Base synchronization effect sequence is invalid")
    end
    private_class_method :validate_base_synchronization!
  end
end
