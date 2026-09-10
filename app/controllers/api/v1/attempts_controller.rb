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
    end
  end
end
