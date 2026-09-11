module Api
  module V1
    class TaskTypesController < BaseController
      def index
        body = pagination_body
        return if performed? || !validate_request!(body)

        cursor = Cursor.new(command: @command, scope: "global")
        position = cursor.decode(body["cursor"])
        relation = TaskType.order(:id)
        relation = relation.where("id > ?", position.fetch(0)) if position
        records = relation.limit(body.fetch("limit") + 1).to_a
        page = records.first(body.fetch("limit"))
        data = { "task_types" => page.map { |record| Serializer.task_type(record) } }
        data["next_cursor"] = cursor.encode([ page.last.id ]) if records.length > page.length
        render_success(data)
      rescue KeyError
        render_malformed_input
      end

      def current_workflow
        body = mutation_body
        return if performed?
        return render_malformed_input unless body.fetch("task_type") == params[:id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:task_type)) do
          WorkflowCatalog::ActivateVersion.call(task_type_id: body.fetch("task_type"),
            workflow_version_id: body.fetch("workflow_version_id"),
            expected_lock_version: body.fetch("expected_lock_version"))
        end
      end
    end
  end
end
