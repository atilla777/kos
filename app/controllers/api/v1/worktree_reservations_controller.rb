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

      def reserve
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        execute_mutation(body, status: :created, serialize: Serializer.method(:worktree)) do
          preconditions = body.fetch("preconditions")
          WorktreeReservations::Reserve.call(repository:, task_number: body.fetch("task_number"),
            branch: body.fetch("branch"), path: body.fetch("path"),
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"))
        end
      end

      def confirm
        mutate_reservation(WorktreeReservations::Confirm) do |body|
          { git_common_dir_digest: body.fetch("git_common_dir_digest"), head_sha: body.fetch("head_sha") }
        end
      end

      def reconcile
        observe(WorktreeReservations::Reconcile)
      end

      def release
        observe(WorktreeReservations::Release)
      end

      private

      def observe(operation)
        mutate_reservation(operation) do |body|
          { observed_state: body.fetch("observed_state"), head_sha: body["head_sha"],
            evidence_digest: body.fetch("evidence_digest") }
        end
      end

      def mutate_reservation(operation)
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["reservation_id"] == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:worktree)) do
          preconditions = body.fetch("preconditions")
          operation.call(repository:, reservation_id: body.fetch("reservation_id"),
            attempt_id: preconditions.fetch("attempt_id"), fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"), **yield(body))
        end
      end
    end
  end
end
