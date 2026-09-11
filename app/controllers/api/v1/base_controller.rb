module Api
  module V1
    class BaseController < ApplicationController
      wrap_parameters false

      COMMANDS = {
        "task_types#index" => "task_type.list",
        "workflow_versions#index" => "workflow.list",
        "workflow_versions#show" => "workflow.get",
        "workflow_versions#export" => "workflow.export",
        "workflow_drafts#show" => "workflow_draft.get",
        "workflow_drafts#update" => "workflow_draft.import",
        "workflow_drafts#validation" => "workflow_draft.validate",
        "workflow_drafts#publication" => "workflow.publish",
        "task_types#current_workflow" => "workflow.activate",
        "tasks#create" => "task.create",
        "tasks#show" => "task.get",
        "attempts#show" => "attempt.get",
        "attempts#claim" => "attempt.claim",
        "attempts#step_context" => "step.context",
        "attempts#renew" => "attempt.renew",
        "attempts#fail_attempt" => "attempt.fail",
        "attempts#needs_human" => "attempt.needs_human",
        "attempts#reconcile" => "attempt.reconcile",
        "worktree_reservations#show" => "worktree.get",
        "worktree_reservations#reserve" => "worktree.reserve",
        "worktree_reservations#confirm" => "worktree.confirm",
        "worktree_reservations#reconcile" => "worktree.reconcile",
        "worktree_reservations#release" => "worktree.release",
        "artifacts#index" => "artifact.list",
        "workflow_steps#complete" => "step.complete"
      }.freeze

      before_action :set_request_context
      before_action :authenticate
      before_action :resolve_repository, if: -> { params[:repository_id] }

      rescue_from StandardError, with: :render_internal_error
      rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_malformed_input
      rescue_from Api::V1::Cursor::Invalid, with: :render_malformed_input
      rescue_from OperationError, with: :render_operation_error

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

      def render_success(data, status: :ok)
        document = envelope.merge("data" => data)
        unless schema_registry.valid?("commands.json", "result", document)
          return render_internal_error
        end

        render json: document, status: status
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

      def render_failure(status, category, code, message, details: nil)
        document = envelope.merge("error" => {
          "category" => category,
          "code" => code,
          "message" => message,
          "retryable" => category == "transient"
        }.tap { |error| error["details"] = details if details })
        render json: document, status: status
      end

      def mutation_body
        document = Kos::JsonParser.parse(request.raw_post)
        return render_malformed_input unless document.is_a?(Hash)

        if document["schema_version"] && document["schema_version"] != "1"
          render_failure(:bad_request, "validation", "unsupported_schema_version", "Schema version is unsupported")
          return
        end
        return render_malformed_input unless request.query_parameters.empty? &&
          schema_registry.valid?("commands.json", "request", document) && document["command"] == @command &&
          (!@repository || document["repository_id"] == @repository.id)

        document.fetch("body")
      rescue JSON::ParserError
        render_malformed_input
      end

      def execute_mutation(body, status:, serialize:, prepare: nil, &operation)
        key = request.headers["Idempotency-Key"].to_s
        return render_malformed_input unless key.match?(IdempotencyRecord::KEY_FORMAT)

        result = Idempotency::Execute.call(command: @command, key: key, body: body,
          status: Rack::Utils.status_code(status), serialize: serialize, repository: @repository,
          error_status: ->(error) { schema_registry.error_status(error.code) }, prepare:) do |prepared|
            operation.call(key, prepared)
          end
        render_success(result.data, status: result.status)
      end

      def render_operation_error(error)
        details = if error.details.is_a?(Array)
          error.details.first&.slice("field")
        elsif error.details.is_a?(Hash)
          error.details.slice("field", "expected", "actual", "resource_id", "retry_after_seconds")
        end
        render_failure(schema_registry.error_status(error.code), schema_registry.error_category(error.code),
          error.code, error.message, details: details.presence)
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
