module Api
  module V1
    class ArtifactsController < BaseController
      def index
        return render_malformed_input if request.query_parameters.key?("task_number")

        body = pagination_body.merge("task_number" => params[:task_task_number])
        return if performed? || !validate_request!(body)

        task = task_for_number(body.fetch("task_number"))
        return render_not_found("task_not_found", "Task not found") unless task

        scope = "#{repository.id}:#{task.id}"
        cursor = Cursor.new(command: @command, scope:)
        position = cursor.decode(body["cursor"])
        relation = task.task_artifacts.order(:created_at, :id)
        if position
          created_at = Time.iso8601(position.fetch(0))
          relation = relation.where("created_at > ? OR (created_at = ? AND id > ?)",
            created_at, created_at, position.fetch(1))
        end
        records = relation.limit(body.fetch("limit") + 1).to_a
        page = records.first(body.fetch("limit"))
        data = { "artifacts" => page.map { |record| Serializer.artifact(record) } }
        if records.length > page.length
          data["next_cursor"] = cursor.encode([ page.last.created_at.utc.iso8601(6), page.last.id ])
        end
        render_success(data)
      rescue ArgumentError, KeyError
        render_malformed_input
      end

      private

      def task_for_number(number)
        sequence = number.delete_prefix("#{repository.task_prefix}-").to_i
        task = repository.tasks.find_by(sequence:)
        task if task&.number == number
      end
    end
  end
end
