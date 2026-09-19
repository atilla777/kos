class WorkflowsController < ApplicationController
  def create
    definition = params.require(:definition_json)
    unless definition.is_a?(ActionController::Parameters)
      raise ActionController::BadRequest, "definition_json must be an object"
    end

    workflow = Workflow.create!(name: required_string(:name), definition_json: definition.to_unsafe_h)

    render json: { workflow: workflow.as_json(only: %i[id name definition_json created_at]) }, status: :created
  end
end
