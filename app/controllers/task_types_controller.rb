class TaskTypesController < ApplicationController
  def create
    task_type = TaskType.create!(name: required_string(:name), workflow: Workflow.find(required_integer(:workflow_id)))

    render json: { task_type: serialize(task_type) }, status: :created
  end

  def update
    task_type = TaskType.find(params[:id])
    task_type.update!(workflow: Workflow.find(required_integer(:workflow_id)))

    render json: { task_type: serialize(task_type) }
  end

  private

  def serialize(task_type)
    task_type.as_json(only: %i[id name workflow_id created_at updated_at])
  end
end
