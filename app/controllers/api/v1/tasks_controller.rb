module Api
  module V1
    class TasksController < BaseController
      def create
        body = mutation_body
        return if performed?

        execute_mutation(body, status: :created, serialize: Serializer.method(:task)) do
          TaskCreation::Create.call(repository: repository, title: body.fetch("title"),
            task_type_name: body.fetch("task_type"))
        end
      end

      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "task_number" => params[:task_number] }
        return if performed? || !validate_request!(body)

        sequence = params[:task_number].delete_prefix("#{repository.task_prefix}-").to_i
        record = repository.tasks.includes(:task_type, :workflow_state, :active_attempt,
          :worktree_reservation).find_by(sequence:)
        return render_not_found("task_not_found", "Task not found") unless record&.number == params[:task_number]

        render_success(Serializer.task(record))
      end
    end
  end
end
