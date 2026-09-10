module Api
  module V1
    class BaseController < ApplicationController
      COMMANDS = {
        "task_types#index" => "task_type.list",
        "workflow_versions#index" => "workflow.list",
        "workflow_versions#show" => "workflow.get",
        "workflow_drafts#show" => "workflow_draft.get",
        "tasks#show" => "task.get",
        "attempts#show" => "attempt.get",
        "worktree_reservations#show" => "worktree.get",
        "artifacts#index" => "artifact.list"
      }.freeze

      before_action :set_request_context
      before_action :authenticate
      before_action :resolve_repository, if: -> { params[:repository_id] }

      rescue_from StandardError, with: :render_internal_error
      rescue_from Api::V1::Cursor::Invalid, with: :render_malformed_input

      private

      attr_reader :repository

      def set_request_context
        @request_id = SecureRandom.uuid
        @command = COMMANDS.fetch("#{controller_name}##{action_name}")
      end

      def authenticate
        authorization = request.authorization.to_s
        return render_failure(:unauthorized, "authentication", "authentication_required",
          "Bearer authentication is required") unless authorization.start_with?("Bearer ")

        supplied = authorization.delete_prefix("Bearer ")
        expected = ENV["KOS_API_TOKEN"].to_s
        valid = supplied.bytesize == expected.bytesize && expected.present? &&
          ActiveSupport::SecurityUtils.secure_compare(supplied, expected)
        render_failure(:unauthorized, "authentication", "invalid_token", "Bearer token is invalid") unless valid
      end

      def resolve_repository
        @repository = Repository.find_by(id: params[:repository_id])
        return if @repository

        render_failure(:forbidden, "authorization", "repository_access_denied", "Repository access denied")
      end

      def validate_request!(body)
        logical_request = { "schema_version" => "1", "command" => @command, "body" => body }
        logical_request["repository_id"] = @repository.id if @repository
        return true if schema_registry.valid?("commands.json", "request", logical_request)

        render_malformed_input
        false
      end

      def render_success(data)
        document = envelope.merge("data" => data)
        unless schema_registry.valid?("commands.json", "result", document)
          return render_internal_error
        end

        render json: document, status: :ok
      end

      def render_not_found(code, message)
        render_failure(:not_found, "not_found", code, message)
      end

      def render_malformed_input(_error = nil)
        render_failure(:bad_request, "validation", "malformed_input", "Request input is malformed")
      end

      def render_internal_error(_error = nil)
        render_failure(:internal_server_error, "internal", "internal_error", "Internal server error")
      end

      def render_failure(status, category, code, message)
        document = envelope.merge("error" => {
          "category" => category,
          "code" => code,
          "message" => message,
          "retryable" => category == "transient"
        })
        render json: document, status: status
      end

      def envelope
        { "schema_version" => "1", "request_id" => @request_id, "command" => @command }
      end

      def schema_registry
        @schema_registry ||= Kos::Cli::SchemaRegistry.new
      end

      def pagination_body
        body = request.query_parameters.dup
        if body["limit"].is_a?(String) && body["limit"].match?(/\A\d+\z/)
          body["limit"] = body["limit"].to_i
        end
        body
      end
    end
  end
end
