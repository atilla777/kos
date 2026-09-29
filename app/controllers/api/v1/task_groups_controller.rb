module Api
  module V1
    class TaskGroupsController < BaseController
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      def index
        groups = scoped_project.task_groups.order(:id)
        groups = groups.where("id > ?", after_id) if after_id
        groups = groups.limit(limit + 1).to_a
        has_more = groups.length > limit
        groups = groups.first(limit)

        render_data({
          task_groups: groups.map { |group| serialize(group, detailed: false) },
          pagination: {
            limit: limit,
            next_after_id: has_more ? groups.last.id : nil
          }
        })
      end

      def show
        render_data({ task_group: serialize(task_group) })
      end

      def create
        group = nil
        created = false

        Project.transaction do
          project = Project.find_or_create_by!(repository: project_repository) do |new_project|
            new_project.name = project_repository.split("/").last
          end
          group = project.task_groups.build(task_group_params)
          created = group.save
          raise ActiveRecord::Rollback unless created
        end

        if created
          render_data({ task_group: serialize(group) }, status: :created)
        else
          render_validation_errors(group)
        end
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      end

      def update
        if task_group.update(task_group_params)
          render_data({ task_group: serialize(task_group) })
        else
          render_validation_errors(task_group)
        end
      end

      def destroy
        if task_group.destroy
          render_data({ task_group: serialize(task_group) })
        else
          render_error("group_not_empty", "Task group with tasks cannot be deleted.", status: :conflict)
        end
      end

      private

      def task_group
        @task_group ||= scoped_project.task_groups.find(params[:id])
      end

      def scoped_project
        @scoped_project ||= Project.find_by!(repository: project_repository)
      end

      def project_repository
        return @project_repository if defined?(@project_repository)

        @project_repository = Project.normalize_repository(params.require(:project))
        raise ActionController::BadRequest unless @project_repository

        @project_repository
      end

      def task_group_params
        params.permit(:kind, :title, :description)
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

      def serialize(group, detailed: true)
        fields = %i[id project_id kind title created_at updated_at]
        fields << :description if detailed
        group.as_json(only: fields).merge(group.progress.stringify_keys)
      end

      def render_validation_errors(record)
        render_error(
          "validation_failed",
          "Task group is invalid.",
          status: :unprocessable_entity,
          details: { fields: record.errors.to_hash }
        )
      end
    end
  end
end
