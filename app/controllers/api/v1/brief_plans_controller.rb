module Api
  module V1
    class BriefPlansController < BaseController
      def show
        plan = BriefPlan.find_by!(brief_task_id: brief.id, request_key: params.require(:key))
        render_data({ plan: serialize(plan) })
      end

      def create
        expected_step = Integer(params.require(:expected_step).to_s, 10)
        raise ActionController::BadRequest if expected_step.negative?

        plan, created = BriefPlan.create_for!(
          brief: brief, claim_id: params.require(:claim_id), expected_step: expected_step,
          key: params.require(:key), entries: params.require(:tasks)
        )
        render_data({ plan: serialize(plan) }, status: created ? :created : :ok)
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      rescue Task::ClaimError => error
        render_error(error.code, "Brief claim or step is no longer valid.", status: :conflict)
      rescue BriefPlan::PlanError => error
        render_error(error.code, "Brief plan cannot be created or changed.", status: :conflict)
      rescue ActiveRecord::RecordInvalid => error
        render_error("validation_failed", "Brief plan contains an invalid task or dependency.",
          status: :unprocessable_entity, details: { fields: error.record.errors.to_hash })
      rescue Task::DependencyCycleError
        render_error("dependency_cycle", "Brief plan contains a dependency cycle.", status: :unprocessable_entity)
      end

      private

      def brief
        @brief ||= Project.find_by!(repository: project_repository).tasks.find(params[:id])
      end

      def project_repository
        value = Project.normalize_repository(params.require(:project))
        raise ActionController::BadRequest unless value

        value
      end

      def serialize(plan)
        { brief_task_id: plan.brief_task_id, key: plan.request_key, tasks: plan.result }
      end
    end
  end
end
