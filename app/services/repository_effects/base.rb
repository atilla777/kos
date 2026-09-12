module RepositoryEffects
  class Base < WorkflowAttempts::Base
    class << self
      private

      def effect_and_locked_task!(repository, effect_id)
        effect = repository.repository_effects.find_by(id: effect_id)
        raise OperationError.new("effect_not_found", "Repository effect not found") unless effect

        task = repository.tasks.lock.find(effect.task_id)
        [ repository.repository_effects.lock.find(effect.id), task ]
      end

      def owning_attempt!(repository, effect, task, attempt_id, fencing_token, now)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        unless effect.current_owner_attempt_id == attempt.id
          raise OperationError.new("fencing_token_stale", "Repository effect ownership is stale")
        end
        attempt
      end
    end
  end
end
