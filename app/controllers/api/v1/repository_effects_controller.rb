module Api
  module V1
    class RepositoryEffectsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "effect_id" => params[:id] }
        return unless validate_request!(body)

        effect = repository.repository_effects.find_by(id: params[:id])
        return render_not_found("effect_not_found", "Repository effect not found") unless effect

        render_success(Serializer.repository_effect(effect))
      end

      def prepare
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        execute_mutation(body, status: :created, serialize: Serializer.method(:repository_effect)) do
          preconditions = body.fetch("preconditions")
          RepositoryEffects::Prepare.call(repository:, task_number: body.fetch("task_number"),
            effect_request: body.fetch("effect_request"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end

      def reconcile
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["effect_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:repository_effect)) do
          preconditions = body.fetch("preconditions")
          RepositoryEffects::Reconcile.call(repository:, effect_id: body.fetch("effect_id"),
            effect_result: body.fetch("effect_result"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
