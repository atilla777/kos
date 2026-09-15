module Api
  module V2
    class PublicationPreflightsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "preflight_id" => params[:id] }
        return unless validate_request!(body)

        preflight = repository.publication_preflights.find_by(id: params[:id])
        return render_not_found("publication_preflight_not_found", "Publication preflight not found") unless preflight

        render_success(Serializer.publication_preflight(preflight))
      end

      def prepare
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        execute_mutation(body, status: :created, serialize: Serializer.method(:publication_preflight)) do
          preconditions = body.fetch("preconditions")
          PublicationPreflights::Prepare.call(repository:, task_number: body.fetch("task_number"),
            candidate_sha: body.fetch("candidate_sha"), remote: body.fetch("remote"),
            base_ref: body.fetch("base_ref"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end

      def reconcile
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["preflight_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:publication_preflight)) do
          preconditions = body.fetch("preconditions")
          PublicationPreflights::Reconcile.call(repository:,
            preflight_id: body.fetch("preflight_id"), observed_remote_oid: body["observed_remote_oid"],
            observed_at: body["observed_at"], evidence_digest: body["evidence_digest"],
            unknown: body["unknown"],
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
