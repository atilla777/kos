module Api
  module V1
    class AttemptsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "attempt_id" => params[:id] }
        return if performed? || !validate_request!(body)

        record = repository.workflow_attempts.includes(:workflow_state).find_by(id: params[:id])
        return render_not_found("attempt_not_found", "Attempt not found") unless record

        render_success(Serializer.attempt(record))
      end

      def claim
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        execute_mutation(body, status: :created, serialize: Serializer.method(:attempt)) do |key|
          WorkflowAttempts::Claim.call(repository:, task_number: body.fetch("task_number"),
            owner_id: body.fetch("owner_id"), lease_seconds: body.fetch("lease_seconds"),
            expected_lock_version: body.dig("preconditions", "expected_lock_version"), idempotency_key: key)
        end
      end

      def renew
        execute_leased_mutation do |body, preconditions|
          WorkflowAttempts::Renew.call(repository:, attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"),
            lease_seconds: body.fetch("lease_seconds"))
        end
      end

      def step_context
        execute_leased_mutation(serialize: ->(context) { context }) do |_body, preconditions|
          WorkflowSteps::CaptureContext.call(repository:, attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end

      def fail_attempt
        finish("failed")
      end

      def needs_human
        finish("needs_human")
      end

      def reconcile
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["attempt_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:attempt)) do
          WorkflowAttempts::Reconcile.call(repository:, attempt_id: body.fetch("attempt_id"),
            observed_state: body.fetch("observed_state"), evidence_digest: body.fetch("evidence_digest"),
            expected_lock_version: body.fetch("expected_lock_version"))
        end
      end

      private

      def finish(state)
        execute_leased_mutation do |body, preconditions|
          WorkflowAttempts::Finish.call(repository:, attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"),
            manifest: body.fetch("result_manifest"), state:)
        end
      end

      def execute_leased_mutation(serialize: Serializer.method(:attempt), &operation)
        body = mutation_body
        return if performed?

        preconditions = body.fetch("preconditions")
        return render_malformed_input unless preconditions["attempt_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize:) do
          operation.call(body, preconditions)
        end
      end
    end
  end
end
