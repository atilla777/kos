module Api
  module V1
    class WorktreeReservationsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "reservation_id" => params[:id] }
        return if performed? || !validate_request!(body)

        record = repository.worktree_reservations.find_by(id: params[:id])
        return render_not_found("reservation_not_found", "Worktree reservation not found") unless record

        render_success(Serializer.worktree(record))
      end
    end
  end
end
