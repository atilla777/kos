module Api
  module V1
    class ProjectsController < BaseController
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      def index
        projects = Project.order(:id)
        projects = projects.where(repository: params[:repository]) if params[:repository].present?
        projects = projects.where("id > ?", after_id) if after_id
        projects = projects.limit(limit + 1).to_a
        has_more = projects.length > limit
        projects = projects.first(limit)

        render_data({
          projects: projects.map { |project| serialize(project) },
          pagination: {
            limit: limit,
            next_after_id: has_more ? projects.last.id : nil
          }
        })
      end

      def show
        render_data({ project: serialize(project) })
      end

      def create
        project = Project.new(project_params)

        if project.save
          render_data({ project: serialize(project) }, status: :created)
        else
          render_validation_errors(project)
        end
      end

      def update
        if project.update(project_params)
          render_data({ project: serialize(project) })
        else
          render_validation_errors(project)
        end
      end

      def destroy
        if project.destroy
          render_data({ project: serialize(project) })
        else
          render_error(
            "project_not_empty",
            "Project with task groups or tasks cannot be deleted.",
            status: :conflict
          )
        end
      end

      private

      def project
        @project ||= Project.find(params[:id])
      end

      def project_params
        params.require(:project).permit(:name, :repository)
      end

      def limit
        @limit ||= pagination_integer(:limit, default: DEFAULT_LIMIT, maximum: MAX_LIMIT)
      end

      def after_id
        return if params[:after_id].blank?

        pagination_integer(:after_id)
      end

      def pagination_integer(name, default: nil, maximum: nil)
        return default if params[name].blank? && default

        value = Integer(params[name], 10)
        valid = value.positive? && (!maximum || value <= maximum)
        raise ActionController::BadRequest unless valid

        value
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      end

      def serialize(project)
        project.as_json(only: %i[id repository name created_at updated_at])
      end

      def render_validation_errors(project)
        repository_taken = project.errors.of_kind?(:repository, :taken)
        render_error(
          repository_taken ? "repository_taken" : "validation_failed",
          repository_taken ? "Repository has already been registered." : "Project is invalid.",
          status: repository_taken ? :conflict : :unprocessable_entity,
          details: { fields: project.errors.to_hash }
        )
      end
    end
  end
end
