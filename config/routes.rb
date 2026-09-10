Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :task_types, only: :index, path: "task-types"
      resources :workflow_versions, only: %i[index show], path: "workflow-versions"
      resources :workflow_drafts, only: :show, param: :workflow_id, path: "workflow-drafts"

      scope "repositories/:repository_id" do
        resources :tasks, only: :show, param: :task_number do
          resources :artifacts, only: :index
        end
        resources :attempts, only: :show
        resources :worktree_reservations, only: :show, path: "worktree-reservations"
      end
    end
  end

  get "api/:schema_version/*path" => "api/unsupported_versions#show",
    constraints: ->(request) { request.path_parameters[:schema_version] != "v1" }
end
