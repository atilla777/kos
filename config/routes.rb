Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :task_types, only: :index, path: "task-types" do
        post :current_workflow, on: :member, path: "current-workflow"
      end
      resources :workflow_versions, only: %i[index show], path: "workflow-versions" do
        get :export, on: :member
      end
      resources :workflow_drafts, only: :show, param: :workflow_id, path: "workflow-drafts" do
        post "", action: :update, on: :member
        get :validation, on: :member
        post :publication, on: :member
      end

      scope "repositories/:repository_id" do
        resources :tasks, only: %i[create show], param: :task_number do
          resources :artifacts, only: :index
          post "attempts/claim", to: "attempts#claim", on: :member
          post "steps/complete", to: "workflow_steps#complete", on: :member
          post "worktree-reservations", to: "worktree_reservations#reserve", on: :member
          post "repository-effects", to: "repository_effects#prepare", on: :member
        end
        resources :attempts, only: :show do
          post :step_context, path: "step-context", on: :member
          post :renew, on: :member
          post :fail, action: :fail_attempt, on: :member
          post :needs_human, path: "needs-human", on: :member
          post :reconcile, on: :member
        end
        resources :worktree_reservations, only: :show, path: "worktree-reservations" do
          post :confirm, on: :member
          post :reconcile, on: :member
          post :release, on: :member
        end
        resources :repository_effects, only: :show, path: "repository-effects" do
          post :reconcile, on: :member
        end
      end
    end
  end

  get "api/:schema_version/*path" => "api/unsupported_versions#show",
    constraints: ->(request) { request.path_parameters[:schema_version] != "v1" }
end
