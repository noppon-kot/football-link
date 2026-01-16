Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  get  "login"  => "sessions#new"
  post "login"  => "sessions#create"
  delete "logout" => "sessions#destroy"

  if Rails.env.development?
    get  "dev/impersonate/:id", to: "sessions#impersonate"
    post "dev/impersonate/:id", to: "sessions#impersonate", as: :dev_impersonate
    delete "dev/impersonate", to: "sessions#stop_impersonating", as: :dev_stop_impersonating
  end

  get "/login/line", to: "sessions#line_login", as: :line_login
  get "/auth/:provider/callback", to: "sessions#line_callback"

  get "mytournaments" => "dashboards#show", as: :mytournaments

  resources :matches, only: [:update]

  resources :tournaments, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
    resources :team_registrations, only: [:new, :create, :update, :destroy] do
      member do
        get :edit_team
        patch :update_team
        get :edit_manager
        patch :update_manager
      end
    end
    post :generate_mock_schedule, on: :member
    member do
      get :teams
      get :groups
      get :fixture
      get :table
      get :knockout
      get :staff, to: "tournament_staffs#show"
      patch :staff, to: "tournament_staffs#update"
      get :my, to: "tournament_my#show"
      get "my/entries/:team_registration_id", to: "tournament_my_entries#show", as: :my_entry
      get "my/entries/:team_registration_id/players", to: "tournament_players#index", as: :my_entry_players
      get "my/entries/:team_registration_id/players/new", to: "tournament_players#new", as: :new_my_entry_player
      post "my/entries/:team_registration_id/players", to: "tournament_players#create", as: :my_entry_players_create
      get "my/entries/:team_registration_id/players/:id/edit", to: "tournament_players#edit", as: :edit_my_entry_player
      patch "my/entries/:team_registration_id/players/:id", to: "tournament_players#update", as: :my_entry_player
      delete "my/entries/:team_registration_id/players/:id", to: "tournament_players#destroy"
      post :generate_mock_schedule
      post :generate_knockout
      post :assign_slot_teams
      patch :update_knockout_teams
      patch :update_points
      patch :update_scores
    end
  end

  resources :admin_messages, only: [:index, :show, :new, :create, :update] do
    resources :admin_message_comments, only: [:create]
  end

  patch "tournaments/:id/approve", to: "tournaments#approve", as: :approve_tournament

  root "tournaments#index"
end
