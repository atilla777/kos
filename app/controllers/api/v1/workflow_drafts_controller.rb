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
    end
  end
end
