class ProjectsController < ApplicationController
  def create
    project = Project.create!(
      name: required_string(:name),
      remote_url: required_string(:remote_url),
      default_branch: required_string(:default_branch)
    )

    render json: { project: project.as_json(only: %i[id name remote_url default_branch created_at updated_at]) },
      status: :created
  end
end
