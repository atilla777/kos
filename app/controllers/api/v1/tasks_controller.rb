module Api
  module V1
    class TasksController < BaseController
      DEFAULT_LIMIT = 50
      MAX_LIMIT = 100

      def index
        tasks = scoped_project.tasks.order(:id)
        tasks = tasks.where("id > ?", after_id) if after_id
        tasks = tasks.limit(limit + 1).to_a
        has_more = tasks.length > limit
        tasks = tasks.first(limit)

        render_data({
          tasks: tasks.map { |task| serialize_brief(task) },
          pagination: {
            limit: limit,
            next_after_id: has_more ? tasks.last.id : nil
          }
        })
      end

      def show
        view = show_view
        render_data({ task: view == "state" ? serialize_state(task) : serialize_context(task, brief: view == "brief") })
      end

      def ready
        tasks = ready_scope
        tasks = tasks.where(kind: params[:kind]) if params[:kind].present?
        tasks = tasks.where(task_group_id: ready_group_id) if params[:task_group_id].present?
        if after_id
          cursor = scoped_project.tasks.find(after_id)
          tasks = tasks.where("tasks.created_at > ? OR (tasks.created_at = ? AND tasks.id > ?)",
            cursor.created_at, cursor.created_at, cursor.id)
        end
        tasks = tasks.order(:created_at, :id).limit(limit + 1).to_a
        has_more = tasks.length > limit
        tasks = tasks.first(limit)

        render_data({
          tasks: tasks.map { |ready_task| serialize_brief(ready_task) },
          pagination: {
            limit: limit,
            next_after_id: has_more ? tasks.last.id : nil
          }
        })
      end

      def current
        current_task = Task.current_for(project: scoped_project, session_id: session_id)
        return render_data({ task: nil, reason: "no_current_task" }) unless current_task

        render_data({ task: compact_context? ? serialize_route(current_task, owned: true) : serialize_context(current_task, owned: true) })
      end

      def step
        brief = brief_view?
        definition = task.workflow.step_at(task.current_step)
        inputs = definition.fetch("inputs").map do |input|
          source_tasks = input.fetch("source") == "task" ? [ task ] : task.blocking_tasks.order(:id).to_a
          matches = source_tasks.filter_map do |source|
            artifact = source.task_artifacts.find_by(key: input.fetch("key"))
            next unless artifact

            artifact.as_json(only: brief ? %i[id task_id key lock_version created_at updated_at] :
              %i[id task_id key content lock_version created_at updated_at])
              .merge("source" => { "task_id" => source.id, "task_title" => source.title })
          end
          { "selector" => input, "artifacts" => matches, "missing" => matches.empty? }
        end
        render_data({ step: {
          "task_id" => task.id, "workflow_id" => task.workflow_id, "current_step" => task.current_step,
          "name" => definition.fetch("name"), "executor" => definition.fetch("executor"),
          "model_tier" => definition["model_tier"], "instructions" => definition.fetch("instructions"),
          "inputs" => inputs, "outputs" => definition.fetch("outputs"),
          **(brief ? {} : { "templates" => definition.fetch("templates", {}) })
        } })
      end

      def advance
        task.advance_step!(claim_id: claim_id, expected_step: Integer(params.require(:expected_step).to_s, 10))
        render_data({ task: serialize_route(task, owned: true) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      end

      def claim
        compact_context?
        claimed_task, reused = Task.claim_for!(
          project: scoped_project,
          task_id: params[:id],
          session_id: session_id
        )
        render_claim(claimed_task, reused)
      rescue Task::ClaimError => error
        render_claim_error(error, params[:id])
      end

      def claim_next
        compact_context?
        claimed_task, reused = Task.claim_next_for!(
          project: scoped_project,
          session_id: session_id,
          kind: params[:kind],
          task_group_id: claim_group_id
        )
        return render_data({ task: nil, reason: "no_ready_tasks" }) unless claimed_task

        render_claim(claimed_task, reused)
      end

      def renew
        task.renew!(claim_id: claim_id)
        render_data({ task: serialize_owned(task) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      end

      def release
        task.release!(
          claim_id: claim_id,
          work_summary: params[:work_summary],
          work_summary_provided: params.key?(:work_summary)
        )
        render_data({ task: serialize_detailed(task) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      end

      def complete
        task.complete!(
          claim_id: claim_id,
          work_summary: params[:work_summary],
          work_summary_provided: params.key?(:work_summary)
        )
        render_data({ task: serialize_detailed(task) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      end

      def reopen
        task.reopen!
        render_data({ task: serialize_detailed(task) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      end

      def create
        task = nil
        created = false

        Project.transaction do
          project = Project.find_or_create_by!(repository: project_repository) do |new_project|
            new_project.name = project_repository.split("/").last
          end
          task = project.tasks.build(task_params)
          task.save!
          task.replace_blockers!(blocked_by_ids) if blocked_by_ids_provided?
          created = true
        end

        if created
          render_data({ task: serialize_detailed(task) }, status: :created)
        else
          render_validation_errors(task)
        end
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      end

      def update
        Task.transaction do
          task.update_from_request!(attributes: task_params, claim_id: params[:claim_id]) if task_params.present?
          task.replace_blockers!(blocked_by_ids) if blocked_by_ids_provided?
        end
        render_data({ task: serialize_detailed(task) })
      rescue Task::ClaimError => error
        render_operation_error(error)
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      end

      def destroy
        deleted_task = serialize_detailed(task)
        task.destroy_safely!
        render_data({ task: deleted_task })
      rescue Task::ClaimError => error
        render_operation_error(error)
      end

      rescue_from Task::DependencyCycleError, with: :render_dependency_cycle

      private

      def task
        @task ||= scoped_project.tasks.find(params[:id])
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

      def task_params
        params.permit(:kind, :title, :description, :work_summary, :task_group_id, :workflow_id)
      end

      def blocked_by_ids_provided?
        params.key?(:blocked_by_ids)
      end

      def blocked_by_ids
        values = params[:blocked_by_ids]
        raise ActionController::BadRequest unless values.is_a?(Array)

        values.map do |value|
          id = Integer(value.to_s, 10)
          raise ActionController::BadRequest unless id.positive?

          id
        end
      rescue ArgumentError, TypeError
        raise ActionController::BadRequest
      end

      def ready_scope
        scoped_project.tasks.ready_at(Time.current)
      end

      def ready_group_id
        pagination_integer(:task_group_id)
      end

      def claim_group_id
        return unless params[:task_group_id].present?

        pagination_integer(:task_group_id)
      end

      def session_id
        value = params.require(:session_id)
        raise ActionController::BadRequest unless value.is_a?(String) && value.strip.present?

        value
      end

      def claim_id
        value = params.require(:claim_id)
        raise ActionController::BadRequest unless value.is_a?(String) && value.present?

        value
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

      def serialize_brief(task)
        task.as_json(only: %i[id project_id task_group_id kind title status created_at updated_at])
          .merge("lease_expired" => task.lease_expired?)
      end

      def serialize_detailed(task)
        task.as_json(only: %i[
          id project_id task_group_id workflow_id current_step kind title description status work_summary session_id
          claimed_at lease_expires_at created_at updated_at
        ]).merge(
          "blocked_by_ids" => task.task_dependencies.order(:blocking_task_id).pluck(:blocking_task_id),
          "lease_expired" => task.lease_expired?
        )
      end

      def serialize_route(task, owned: false)
        definition = task.workflow.step_at(task.current_step)
        result = serialize_detailed(task).slice(
          "id", "project_id", "workflow_id", "current_step", "title", "status", "lease_expires_at"
        ).merge("step" => {
          "name" => definition.fetch("name"), "executor" => definition.fetch("executor"),
          "model_tier" => definition["model_tier"]
        })
        result["claim_id"] = task.claim_id if owned
        result
      end

      def serialize_owned(task)
        serialize_detailed(task).merge("claim_id" => task.claim_id)
      end

      def serialize_context(task, owned: false, brief: false)
        detailed = serialize_detailed(task).except("blocked_by_ids")
        detailed = detailed.except("description", "work_summary", "session_id") if brief
        serialized = detailed.merge(
          "artifacts" => context_artifacts(task, brief: brief),
          "task_group" => serialize_context_group(task.task_group, brief: brief),
          "blocked_by" => context_tasks(task.blocking_tasks, :blocked_by_after_id, brief: brief),
          "dependency_artifacts" => context_dependency_artifacts(task, brief: brief),
          "blocks" => context_tasks(task.dependent_tasks, :blocks_after_id, brief: brief),
          "availability" => task.availability_at,
          "pagination" => context_pagination
        )
        serialized["claim_id"] = task.claim_id if owned
        serialized
      end

      def serialize_state(task)
        records, = paginate_context(task.task_artifacts.select(:id, :key, :lock_version), :artifacts, :artifact_after_id)
        {
          "id" => task.id, "title" => task.title, "status" => task.status,
          "current_step" => task.current_step, "availability" => task.availability_at,
          "artifacts" => records.map { |artifact| artifact.as_json(only: %i[key lock_version]) },
          "pagination" => context_pagination.fetch(:artifacts)
        }
      end

      def context_artifacts(task, brief: false)
        records, = paginate_context(task.task_artifacts, :artifacts, :artifact_after_id)
        records.map { |artifact| serialize_context_artifact(artifact, brief: brief) }
      end

      def context_dependency_artifacts(task, brief: false)
        relation = TaskArtifact.where(task_id: task.blocking_tasks.select(:id)).includes(:task)
        records, = paginate_context(relation, :dependency_artifacts, :dependency_artifact_after_id)
        records.map do |artifact|
          {
            "id" => artifact.id,
            **(brief ? {} : { "content" => artifact.content }),
            "source" => {
              "task_id" => artifact.task_id,
              "task_title" => artifact.task.title,
              "key" => artifact.key,
              "lock_version" => artifact.lock_version
            }
          }
        end
      end

      def context_tasks(relation, cursor_name, brief: false)
        collection_name = cursor_name == :blocked_by_after_id ? :blocked_by : :blocks
        records, = paginate_context(relation, collection_name, cursor_name)
        records.map do |related_task|
          related_task.as_json(only: brief ? %i[id kind title status] : %i[id kind title status work_summary]).merge(
            "lease_expired" => related_task.lease_expired?
          )
        end
      end

      def serialize_context_artifact(artifact, brief: false)
        artifact.as_json(only: brief ? %i[id task_id key lock_version created_at updated_at] :
          %i[id task_id key content lock_version created_at updated_at])
      end

      def serialize_context_group(group, brief: false)
        return unless group

        group.as_json(only: brief ? %i[id kind title] : %i[id kind title description])
      end

      def context_pagination
        @context_pagination.transform_values do |page|
          {
            "limit" => context_limit,
            "complete" => page[:next_after_id].nil?,
            "after_parameter" => page[:after_parameter],
            "next_after_id" => page[:next_after_id]
          }
        end
      end

      def paginate_context(relation, collection_name, cursor_name)
        records = relation.order(:id)
        cursor = context_after_id(cursor_name)
        records = records.where("#{relation.klass.table_name}.id > ?", cursor) if cursor
        records = records.limit(context_limit + 1).to_a
        has_more = records.length > context_limit
        records = records.first(context_limit)
        context_pagination_state[collection_name] = {
          after_parameter: cursor_name.to_s,
          next_after_id: has_more ? records.last.id : nil
        }
        [ records, has_more ]
      end

      def context_pagination_state
        @context_pagination ||= {}
      end

      def context_limit
        @context_limit ||= pagination_integer(:context_limit, default: DEFAULT_LIMIT, maximum: MAX_LIMIT)
      end

      def context_after_id(name)
        return if params[name].blank?

        pagination_integer(name)
      end

      def render_claim(claimed_task, reused)
        render_data({
          task: compact_context? ? serialize_route(claimed_task, owned: true) : serialize_context(claimed_task, owned: true),
          claim_status: reused ? "existing" : "created"
        })
      end

      def compact_context?
        return false if params[:context].blank?
        raise ActionController::BadRequest unless params[:context] == "route"

        true
      end

      def brief_view?
        return false unless params.key?(:view)
        raise ActionController::BadRequest unless params[:view] == "brief"

        true
      end

      def show_view
        return unless params.key?(:view)
        raise ActionController::BadRequest unless %w[brief state].include?(params[:view])

        params[:view]
      end

      def render_claim_error(error, task_id)
        messages = {
          "task_blocked" => "Task has unfinished blockers.",
          "task_already_claimed" => "Task already has an active claim.",
          "session_has_active_task" => "Session already has an active task in this project.",
          "invalid_transition" => "Task cannot be claimed from its current state."
        }
        render_error(error.code, messages.fetch(error.code), status: :conflict, details: { task_id: task_id.to_i })
      end

      def render_operation_error(error)
        messages = {
          "claim_mismatch" => "Claim does not own this task.",
          "lease_expired" => "Claim lease has expired.",
          "invalid_transition" => "Task cannot perform this operation from its current state.",
          "task_already_claimed" => "Task has an active claim.",
          "task_has_dependents" => "Task is required by another task.",
          "task_has_started_dependents" => "Dependent work has already started.",
          "step_conflict" => "Task has moved to another step."
        }
        render_error(error.code, messages.fetch(error.code), status: :conflict, details: { task_id: task.id })
      end


      def render_dependency_cycle
        render_error("dependency_cycle", "Task dependencies would create a cycle.", status: :unprocessable_entity)
      end

      def render_validation_errors(record)
        render_error(
          "validation_failed",
          "Task is invalid.",
          status: :unprocessable_entity,
          details: { fields: record.errors.to_hash }
        )
      end
    end
  end
end
