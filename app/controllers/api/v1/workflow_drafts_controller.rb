module Api
  module V1
    class WorkflowDraftsController < BaseController
      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "workflow_id" => params[:workflow_id] }
        return if performed? || !validate_request!(body)

        record = WorkflowDraft.includes(:task_type).find_by(workflow_id: params[:workflow_id])
        return render_not_found("workflow_draft_not_found", "Workflow draft not found") unless record

        render_success(Serializer.workflow_draft(record))
      end

      def update
        body = mutation_body
        return if performed?
        return render_malformed_input unless body.fetch("workflow_id") == params[:workflow_id] &&
          body.dig("definition", "workflow_id") == params[:workflow_id]

        execute_mutation(body, status: :ok, serialize: Serializer.method(:workflow_draft)) do
          WorkflowCatalog::ImportDraft.call(workflow_id: body.fetch("workflow_id"),
            definition: body.fetch("definition"), expected_lock_version: body.fetch("expected_lock_version"))
        end
      end

      def validation
        return render_malformed_input if request.query_parameters.any?

        body = { "workflow_id" => params[:workflow_id] }
        return if performed? || !validate_request!(body)

        draft = WorkflowDraft.includes(:task_type).find_by(workflow_id: params[:workflow_id])
        return render_not_found("workflow_draft_not_found", "Workflow draft not found") unless draft

        errors = WorkflowCatalog::DefinitionValidator.new(draft.definition, task_type: draft.task_type).errors
        render_success({ "valid" => errors.empty?, "errors" => errors })
      end

      def publication
        body = mutation_body
        return if performed?
        return render_malformed_input unless body.fetch("workflow_id") == params[:workflow_id]

        execute_mutation(body, status: :created, serialize: Serializer.method(:workflow_version)) do
          WorkflowCatalog::PublishDraft.call(workflow_id: body.fetch("workflow_id"),
            expected_lock_version: body.fetch("expected_lock_version"))
        end
      end
    end
  end
end
