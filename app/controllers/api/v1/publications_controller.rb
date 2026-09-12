module Api
  module V1
    class PublicationsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "publication_id" => params[:id] }
        return unless validate_request!(body)

        publication = repository.publications.find_by(id: params[:id])
        return render_not_found("publication_not_found", "Publication not found") unless publication

        render_success(Serializer.publication(publication))
      end

      def prepare
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        execute_mutation(body, status: :created, serialize: Serializer.method(:publication)) do
          preconditions = body.fetch("preconditions")
          Publications::Prepare.call(repository:, task_number: body.fetch("task_number"),
            candidate_sha: body.fetch("candidate_sha"), remote: body.fetch("remote"),
            base_ref: body.fetch("base_ref"), expected_remote_oid: body.fetch("expected_remote_oid"),
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end

      def reconcile
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["publication_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:publication)) do
          preconditions = body.fetch("preconditions")
          Publications::Reconcile.call(repository:, publication_id: body.fetch("publication_id"),
            candidate_sha: body.fetch("candidate_sha"), observed_remote_tip: body.fetch("observed_remote_tip"),
            candidate_reachable: body.fetch("candidate_reachable"), observed_at: body.fetch("observed_at"),
            evidence_digest: body.fetch("evidence_digest"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
