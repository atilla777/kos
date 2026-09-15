module Api
  module V2
    class PublicationsController < BaseController
      def prepare_observed
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["preflight_id"] == params[:preflight_id]

        execute_mutation(body, status: :created, serialize: Serializer.method(:publication)) do
          preconditions = body.fetch("preconditions")
          Publications::PrepareObserved.call(repository:, preflight_id: body.fetch("preflight_id"),
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end
    end
  end
end
