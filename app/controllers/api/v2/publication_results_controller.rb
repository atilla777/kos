module Api
  module V2
    class PublicationResultsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "publication_id" => params[:publication_id] }
        return unless validate_request!(body)

        result = repository.publication_results.find_by(publication_id: params[:publication_id])
        return render_not_found("publication_result_not_found", "Publication result not found") unless result

        render_success(Serializer.publication_result(result))
      end

      def record
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["publication_id"] == params[:publication_id]

        execute_mutation(body, status: :created, serialize: Serializer.method(:publication_result)) do
          preconditions = body.fetch("preconditions")
          PublicationResults::Record.call(repository:, publication_id: body.fetch("publication_id"),
            result_manifest: body.fetch("result_manifest"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
