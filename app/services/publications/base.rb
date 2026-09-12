module Publications
  class Base < WorkflowAttempts::Base
    class << self
      private

      def publication_and_locked_task!(repository, publication_id)
        publication = repository.publications.find_by(id: publication_id)
        raise OperationError.new("publication_not_found", "Publication not found") unless publication

        task = repository.tasks.lock.find(publication.task_id)
        [ repository.publications.lock.find(publication.id), task ]
      end

      def owning_attempt!(repository, publication, task, attempt_id, fencing_token, now)
        attempt = repository.workflow_attempts.lock.find_by(id: attempt_id)
        raise OperationError.new("attempt_not_found", "Attempt not found") unless attempt

        check_lease!(attempt, task, fencing_token, now)
        unless publication.current_owner_attempt_id == attempt.id
          raise OperationError.new("fencing_token_stale", "Publication ownership is stale")
        end
        attempt
      end
    end
  end
end
