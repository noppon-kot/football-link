Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  get  "login"  => "sessions#new"
  post "login"  => "sessions#create"
  delete "logout" => "sessions#destroy"

  get "dashboard" => "dashboards#show"

  resources :tournaments, only: [:index, :show, :new, :create, :edit, :update] do
    resources :team_registrations, only: [:new, :create, :update, :destroy]
  end

  resources :admin_messages, only: [:index, :show, :new, :create, :update] do
    resources :admin_message_comments, only: [:create]
  end

  patch "tournaments/:id/approve", to: "tournaments#approve", as: :approve_tournament

  root "tournaments#index"
end
