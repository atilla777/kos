class TasksController < ApplicationController
  def create
    task = lifecycle.create!(
      project: Project.find(required_integer(:project_id)),
      task_type: TaskType.find(required_integer(:task_type_id)),
      title: required_string(:title),
      description_markdown: required_string(:description_markdown),
      parent: find_optional_task(:parent_id),
      blockers: find_tasks(optional_integer_array(:blocker_ids, default: []))
    )

    render json: serialize(task), status: :created
  end

  def show
    render json: serialize(lifecycle.show!(params[:id]))
  end

  def update
    attributes = { task_id: params[:id] }
    attributes[:description_markdown] = required_string(:description_markdown) if params.key?(:description_markdown)
    attributes[:parent] = find_optional_task(:parent_id) if params.key?(:parent_id)
    attributes[:blockers] = find_tasks(optional_integer_array(:blocker_ids)) if params.key?(:blocker_ids)
    raise ActionController::BadRequest, "no editable task fields were provided" if attributes.one?

    render json: serialize(lifecycle.update_definition!(**attributes))
  end

  def claim_next
    task = lifecycle.claim_next!(
      project: Project.find(required_integer(:project_id)),
      owner_id: required_string(:owner_id)
    )
    return head :no_content unless task

    render json: serialize(task)
  end

  def resume
    Task.find(params[:id])
    takeover_confirmed = params.fetch(:takeover_confirmed, false)
    unless takeover_confirmed == true || takeover_confirmed == false
      raise ActionController::BadRequest, "takeover_confirmed must be a boolean"
    end

    task = lifecycle.resume!(task_id: params[:id], owner_id: required_string(:owner_id), takeover_confirmed:)
    render json: serialize(task)
  end

  def report_attempt
    task = lifecycle.report_attempt!(
      task_id: params[:id],
      owner_id: required_string(:owner_id),
      claim_version: required_integer(:claim_version),
      step: required_string(:step),
      outcome: required_string(:outcome)
    )
    render json: serialize(task)
  end

  def cancel
    Task.find(params[:id])
    render json: serialize(lifecycle.cancel!(task_id: params[:id]))
  end

  private

  def lifecycle
    @lifecycle ||= TaskLifecycle.new
  end

  def find_optional_task(name)
    id = optional_integer(name)
    Task.find(id) if id
  end

  def find_tasks(ids)
    return [] if ids.empty?

    Task.find(ids)
  end

  def serialize(task)
    task = Task.includes(:workflow, :blockers).find(task.id)
    workflow = task.workflow
    step = workflow.definition_json.fetch("steps").find { |candidate| candidate.fetch("id") == task.current_step }

    {
      task: task.as_json(only: %i[id project_id task_type_id workflow_id parent_id title description_markdown status
        current_step owner_id claim_version lease_expires_at created_at updated_at]).merge("blocker_ids" => task.blocker_ids.sort),
      workflow: workflow.as_json(only: %i[id name definition_json created_at]),
      step:
    }
  end
end
