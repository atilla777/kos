module Api
  module V1
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
      rescue_from ActiveRecord::RecordNotUnique, with: :render_repository_conflict
      rescue_from ActiveRecord::InvalidForeignKey, with: :render_project_not_empty
      rescue_from ActiveRecord::StatementTimeout, with: :render_database_busy
      rescue_from ActionController::ParameterMissing, with: :render_bad_request
      rescue_from ActionController::BadRequest, with: :render_bad_request
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

      private

      def render_data(data, status: :ok)
        render json: { data: data }, status: status
      end

      def render_error(code, message, status:, details: nil)
        error = { code: code, message: message }
        error[:details] = details if details.present?
        render json: { error: error }, status: status
      end

      def render_not_found
        render_error("not_found", "Resource not found.", status: :not_found)
      end

      def render_repository_conflict
        render_error(
          "repository_taken",
          "Repository has already been registered.",
          status: :conflict
        )
      end

      def render_bad_request
        render_error("invalid_request", "Required request data is missing.", status: :bad_request)
      end

      def render_project_not_empty
        render_error(
          "project_not_empty",
          "Project with task groups or tasks cannot be deleted.",
          status: :conflict
        )
      end

      def render_database_busy
        render_error(
          "database_busy",
          "Database is temporarily busy; retry after checking current task state.",
          status: :service_unavailable
        )
      end
    end
  end
end
