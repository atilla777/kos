module Api
  module V1
    class TaskArtifactsController < BaseController
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      def index
        artifacts = task.task_artifacts.order(:id)
        artifacts = artifacts.where("id > ?", after_id) if after_id
        artifacts = artifacts.limit(limit + 1).to_a
        has_more = artifacts.length > limit
        artifacts = artifacts.first(limit)
        render_data({ artifacts: artifacts.map { |artifact| serialize(artifact) },
          pagination: { limit: limit, next_after_id: has_more ? artifacts.last.id : nil } })
      end

      def show
        render_data({ artifact: serialize(artifact) })
      end

      def update
        saved_artifact = task.put_artifact!(
          key: artifact_key,
          content: content,
          claim_id: claim_id,
          expected_lock_version: expected_lock_version(allow_nil: true),
          expected_step: expected_step
        )
        render_data({ artifact: serialize(saved_artifact) })
      rescue Task::ClaimError => error
        render_claim_error(error)
      rescue TaskArtifact::VersionConflict
        render_version_conflict
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      end

      def destroy
        deleted_artifact = task.delete_artifact!(
          key: artifact_key,
          claim_id: claim_id,
          expected_lock_version: expected_lock_version(allow_nil: false)
        )
        render_data({ artifact: serialize(deleted_artifact) })
      rescue Task::ClaimError => error
        render_claim_error(error)
      rescue TaskArtifact::VersionConflict
        render_version_conflict
      end

      private

      def scoped_project
        @scoped_project ||= Project.find_by!(repository: project_repository)
      end

      def task
        @task ||= scoped_project.tasks.find(params[:task_id])
      end

      def artifact
        @artifact ||= task.task_artifacts.find_by!(key: artifact_key)
      end

      def project_repository
        repository = Project.normalize_repository(params.require(:project))
        raise ActionController::BadRequest unless repository

        repository
      end

      def artifact_key
        value = params[:key]
        raise ActionController::BadRequest unless value.is_a?(String) && value.strip.present?

        value
      end

      def content
        value = params.require(:content)
        raise ActionController::BadRequest unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?

        value
      end

      def claim_id
        value = params.require(:claim_id)
        raise ActionController::BadRequest unless value.is_a?(String) && value.present?

        value
      end

      def expected_lock_version(allow_nil:)
        raise ActionController::BadRequest unless params.key?(:lock_version)

        value = params[:lock_version]
        return if allow_nil && value.nil?
        raise ActionController::BadRequest unless value.is_a?(Integer) && value >= 0

        value
      end

      def expected_step
        return unless params.key?(:expected_step)

        value = params[:expected_step]
        raise ActionController::BadRequest unless value.is_a?(Integer) && value >= 0

        value
      end

      def limit
        @limit ||= positive_integer(:limit, default: DEFAULT_LIMIT, maximum: MAX_LIMIT)
      end

      def after_id
        return if params[:after_id].blank?

        positive_integer(:after_id)
      end

      def positive_integer(name, default: nil, maximum: nil)
        return default if params[name].blank? && default

        value = Integer(params[name], 10)
        raise ActionController::BadRequest unless value.positive? && (!maximum || value <= maximum)

        value
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      end

      def serialize(record)
        record.as_json(only: %i[id task_id key content lock_version created_at updated_at])
      end

      def render_claim_error(error)
        messages = {
          "claim_mismatch" => "Claim does not own this task.",
          "lease_expired" => "Claim lease has expired.",
          "invalid_transition" => "Task cannot perform this operation from its current state.",
          "step_conflict" => "Task has moved to another step."
        }
        render_error(error.code, messages.fetch(error.code), status: :conflict, details: { task_id: task.id })
      end

      def render_version_conflict
        render_error(
          "artifact_version_conflict",
          "Artifact state does not match the expected version.",
          status: :conflict,
          details: { task_id: task.id, key: artifact_key }
        )
      end

      def render_validation_errors(record)
        render_error(
          "validation_failed",
          "Artifact is invalid.",
          status: :unprocessable_entity,
          details: { fields: record.errors.to_hash }
        )
      end
    end
  end
end
