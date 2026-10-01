module Api
  module V1
    class WorkflowsController < BaseController
      def index
        brief = brief_view?
        limit = Integer(params.fetch(:limit, 50).to_s, 10)
        raise ActionController::BadRequest unless limit.between?(1, 100)

        after_id = params[:after_id] && Integer(params[:after_id].to_s, 10)
        raise ActionController::BadRequest if after_id && after_id <= 0

        relation = Workflow.visible_to(Project.find_by(repository: project_repository)).order(:id)
        relation = relation.where("id > ?", after_id) if after_id
        records = relation.limit(limit + 1).to_a
        more = records.length > limit
        records = records.first(limit)
        render_data({ workflows: records.map { |workflow| serialize(workflow, brief: brief) },
          pagination: { limit: limit, next_after_id: more ? records.last.id : nil } })
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      end

      def show
        render_data({ workflow: serialize(workflow) })
      end

      def create
        raise ActionController::BadRequest if params.key?(:global) && params[:global] != true

        created = nil
        Project.transaction do
          if params[:global] == true
            raise ActionController::BadRequest if params.key?(:project)

            created = Workflow.create!(name: params.require(:name), steps: params.require(:steps))
          else
            project = Project.find_or_create_by!(repository: project_repository) do |record|
              record.name = project_repository.split("/").last
            end
            created = project.workflows.create!(name: params.require(:name), steps: params.require(:steps))
          end
        end
        render_data({ workflow: serialize(created) }, status: :created)
      rescue ActiveRecord::RecordInvalid => error
        render_error("validation_failed", "Workflow is invalid.", status: :unprocessable_entity,
          details: { fields: error.record.errors.to_hash })
      end

      def destroy
        if workflow.tasks.exists?
          return render_error("workflow_in_use", "Workflow is in use.", status: :conflict)
        end

        deleted = serialize(workflow)
        workflow.destroy!
        render_data({ workflow: deleted })
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey
        render_error("workflow_in_use", "Workflow is in use.", status: :conflict)
      end

      private

      def project_repository
        @project_repository ||= Project.normalize_repository(params.require(:project))
        raise ActionController::BadRequest unless @project_repository

        @project_repository
      end

      def workflow
        @workflow ||= Workflow.visible_to(Project.find_by(repository: project_repository)).find(params[:id])
      end

      def serialize(record, brief: false)
        record.as_json(only: brief ? %i[id project_id name] : %i[id project_id name steps created_at updated_at])
      end

      def brief_view?
        return false unless params.key?(:view)
        raise ActionController::BadRequest unless params[:view] == "brief"

        true
      end
    end
  end
end
