module Api
  module V1
    class WorkflowVersionsController < BaseController
      ASSOCIATIONS = [ :task_type, { workflow_states: [ :artifact_templates, :workflow_state_effects,
        { artifact_requirements: :artifact_requirement_states } ] },
        { workflow_transitions: [ :from_state, :to_state, :workflow_transition_conditions ] } ].freeze

      def index
        body = pagination_body
        return if performed? || !validate_request!(body)

        cursor = Cursor.new(command: @command, scope: "global")
        position = cursor.decode(body["cursor"])
        relation = WorkflowVersion.where.not(published_at: nil).includes(:task_type).order(:published_at, :id)
        if position
          published_at = Time.iso8601(position.fetch(0))
          relation = relation.where("published_at > ? OR (published_at = ? AND id > ?)",
            published_at, published_at, position.fetch(1))
        end
        records = relation.limit(body.fetch("limit") + 1).to_a
        page = records.first(body.fetch("limit"))
        data = { "workflows" => page.map { |record| Serializer.workflow_summary(record) } }
        if records.length > page.length
          data["next_cursor"] = cursor.encode([ page.last.published_at.utc.iso8601(6), page.last.id ])
        end
        render_success(data)
      rescue ArgumentError, KeyError
        render_malformed_input
      end

      def show
        return render_malformed_input if request.query_parameters.any?

        body = { "workflow_version_id" => params[:id] }
        return if performed? || !validate_request!(body)

        record = WorkflowVersion.where.not(published_at: nil).includes(*ASSOCIATIONS).find_by(id: params[:id])
        return render_not_found("workflow_version_not_found", "Workflow version not found") unless record

        render_success(Serializer.workflow_version(record))
      end

      def export
        return render_malformed_input if request.query_parameters.any?

        body = { "workflow_version_id" => params[:id] }
        return if performed? || !validate_request!(body)

        record = WorkflowVersion.where.not(published_at: nil).includes(*ASSOCIATIONS).find_by(id: params[:id])
        return render_not_found("workflow_version_not_found", "Workflow version not found") unless record

        render_success(WorkflowCatalog::CanonicalDefinition.from_record(record))
      end
    end
  end
end
