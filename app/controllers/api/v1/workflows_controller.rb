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
        raise ActionController::BadRequest if params.key?(:based_on_id) && params[:global] == true
        raise ActionController::BadRequest if params.key?(:based_on_id) && params.key?(:name)

        created = nil
        Project.transaction do
          if params[:global] == true
            raise ActionController::BadRequest if params.key?(:project)

            created = Workflow.create!(name: params.require(:name), steps: params.require(:steps))
          else
            project = Project.find_or_create_by!(repository: project_repository) do |record|
              record.name = project_repository.split("/").last
            end
            if params.key?(:based_on_id)
              source = project.workflows.find(params[:based_on_id])
              raise ActionController::BadRequest unless source.base_workflow_id && source.edition

              latest = project.workflows.where(base_workflow_id: source.base_workflow_id).maximum(:edition)
              raise ActiveRecord::RecordNotUnique, "Stale project edition" if latest != source.edition

              created = project.workflows.create!(name: source.name.sub(/v\d+\z/, "v#{source.edition + 1}"),
                steps: params.require(:steps), base_workflow: source.base_workflow, edition: source.edition + 1)
            else
              created = project.workflows.create!(name: params.require(:name), steps: params.require(:steps))
            end
          end
        end
        render_data({ workflow: serialize(created) }, status: :created)
      rescue ActiveRecord::RecordInvalid => error
        render_error("validation_failed", "Workflow is invalid.", status: :unprocessable_entity,
          details: { fields: error.record.errors.to_hash })
      rescue ActiveRecord::RecordNotUnique
        render_error("workflow_version_conflict", "A newer project edition exists.", status: :conflict)
      end

      def install_base
        installed = nil
        Project.transaction do
          project = Project.find_or_create_by!(repository: project_repository) do |record|
            record.name = project_repository.split("/").last
          end
          bases = %w[Brief Execution Fix].map do |kind|
            Workflow.find_by!(project_id: nil, name: "KOS Base #{kind} v1")
          end
          installed = bases.map do |base|
            existing = project.workflows.find_by(base_workflow_id: base.id, edition: 1)
            if existing
              unless existing.steps == base.steps
                raise ActiveRecord::RecordInvalid.new(existing)
              end
              existing
            else
              project.workflows.create!(name: base.name.sub("Base ", ""), steps: base.steps,
                base_workflow: base, edition: 1)
            end
          end
        end
        render_data({ workflows: installed.map { |workflow| serialize(workflow) } })
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        render_error("workflow_install_conflict", "Project base workflows conflict with installed definitions.", status: :conflict)
      rescue ActiveRecord::RecordNotFound
        render_error("workflow_base_missing", "Install base workflows before connecting this project.", status: :conflict)
      end

      def destroy
        if workflow.tasks.exists? || workflow.project_copies.exists?
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
        record.as_json(only: brief ? %i[id project_id name base_workflow_id edition] :
          %i[id project_id name base_workflow_id edition steps created_at updated_at])
      end

      def brief_view?
        return false unless params.key?(:view)
        raise ActionController::BadRequest unless params[:view] == "brief"

        true
      end
    end
  end
end
