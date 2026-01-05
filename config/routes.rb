Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  resources :tournaments, only: [:index, :show, :new, :create, :edit, :update] do
    resources :team_registrations, only: [:new, :create]
  end

  root "tournaments#index"
end
