Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :projects, only: :create
  resources :workflows, only: :create
  resources :task_types, only: :create
  patch "task_types/:id", to: "task_types#update", as: :task_type

  post "tasks/claim-next", to: "tasks#claim_next"
  post "tasks/create-and-claim", to: "tasks#create_and_claim"
  get "tasks/show-owned", to: "tasks#show_owned"
  get "tasks/resumable", to: "tasks#resumable"
  resources :tasks, only: %i[create show] do
    member do
      post :claim
      post :resume
      post "report-attempt", action: :report_attempt
      post :cancel
    end
  end
  patch "tasks/:id", to: "tasks#update"
end
