Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :projects, only: %i[index show create update destroy]
      resources :task_groups, path: "task-groups", only: %i[index show create update destroy]
      resources :workflows, only: %i[index show create destroy]
      resources :tasks, only: %i[index show create update destroy] do
        get "brief-plan/:key", to: "brief_plans#show", on: :member, as: :brief_plan, format: false
        post "brief-plan", to: "brief_plans#create", on: :member
        get "step", to: "tasks#step", on: :member
        post "advance", to: "tasks#advance", on: :member
        get "artifacts", to: "task_artifacts#index"
        get "artifacts/:key", to: "task_artifacts#show", as: :artifact, format: false
        put "artifacts/:key", to: "task_artifacts#update", format: false
        delete "artifacts/:key", to: "task_artifacts#destroy", format: false
        collection do
          get :ready
          get :current
          post "claim-next", action: :claim_next
        end
        member do
          post :claim
          post :renew
          post :release
          post :complete
          post :reopen
        end
      end
      match "*unmatched", to: "errors#not_found", via: :all
    end
  end
end
