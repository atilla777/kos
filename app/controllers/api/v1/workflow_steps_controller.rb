module Api
  module V1
    class WorkflowStepsController < BaseController
      def complete
        body = mutation_body
        return if performed?
        return render_malformed_input unless body["task_number"] == params[:task_number]

        preconditions = body.fetch("preconditions")
        artifacts = body.dig("result_manifest", "artifacts")
        prepare = lambda do
          RepositoryEvidence::VerifyArtifacts.call(repository:, task_number: body.fetch("task_number"), artifacts:)
        end
        serialize = lambda do |result|
          { "task" => Serializer.task(result.task),
            "artifacts" => result.artifacts.map { Serializer.artifact(_1) } }
        end
        execute_mutation(body, status: :ok, serialize:, prepare:) do |_key, verification|
          WorkflowSteps::Complete.call(repository:, task_number: body.fetch("task_number"),
            to_status: body.fetch("to_status"), attempt_id: preconditions.fetch("attempt_id"),
            fencing_token: preconditions.fetch("fencing_token"),
            expected_lock_version: preconditions.fetch("expected_lock_version"),
            manifest: body.fetch("result_manifest"), verified_evidence: verification)
        end
      end
    end
  end
end
