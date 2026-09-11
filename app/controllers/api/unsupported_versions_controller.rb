module Api
  class UnsupportedVersionsController < Api::V1::BaseController
    COMMAND_PATTERNS = {
      %r{\Atask-types\z} => "task_type.list",
      %r{\Aworkflow-versions\z} => "workflow.list",
      %r{\Aworkflow-versions/[^/]+\z} => "workflow.get",
      %r{\Aworkflow-drafts/[^/]+\z} => "workflow_draft.get",
      %r{\Arepositories/[^/]+/tasks/[^/]+/artifacts\z} => "artifact.list",
      %r{\Arepositories/[^/]+/attempts/[^/]+/step-context\z} => "step.context",
      %r{\Arepositories/[^/]+/tasks/[^/]+\z} => "task.get",
      %r{\Arepositories/[^/]+/attempts/[^/]+\z} => "attempt.get",
      %r{\Arepositories/[^/]+/worktree-reservations/[^/]+\z} => "worktree.get"
    }.freeze

    def show
      if @command == "unknown"
        return render_failure(:bad_request, "validation", "unknown_command", "Command is unknown")
      end

      render_failure(:bad_request, "validation", "unsupported_schema_version", "Schema version is unsupported")
    end

    private

    def set_request_context
      @request_id = SecureRandom.uuid
      @command = COMMAND_PATTERNS.find { |pattern, _command| pattern.match?(params[:path]) }&.last || "unknown"
    end
  end
end
