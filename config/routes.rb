Rails.application.routes.draw do
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  devise_for :users,
             controllers: {
               sessions: "users/sessions",
               registrations: "users/registrations",
               confirmations: "users/confirmations",
               passwords: "users/passwords",
               unlocks: "users/unlocks"
             }

  # Custom confirmation routes
  devise_scope :user do
    get "users/awaiting_confirmation", to: "users/confirmations#awaiting_confirmation", as: :awaiting_confirmation_users_confirmation
    post "users/confirmation/resend", to: "users/confirmations#resend", as: :resend_users_confirmation
    post "users/sign_out_everywhere", to: "users/sessions#destroy_others", as: :sign_out_everywhere
  end

  # Team invitations (ACC-03)
  resources :invitations, only: :show, param: :token do
    member do
      post :accept
      post :sign_up
    end
  end

  # Client links (PLT-12): the only way clients reach documents.
  get "c/:token", to: "client_links#show", as: :client_link
  post "c/:token/fresh", to: "client_links#request_fresh", as: :request_fresh_client_link
  post "c/:token/quote/update", to: "client/quotes#request_update", as: :request_quote_update
  get "c/:token/quote/files/:id", to: "client/quote_files#show", as: :client_quote_file
  get "c/:token/quote/pdf", to: "client/quotes#pdf", as: :client_quote_pdf # QTE-03

  # Admin routes
  namespace :admin do
    # Clients (CLI-01)
    resources :clients do
      member do
        patch :archive
        patch :restore
        get :picked
        patch "contact_methods/:contact_method_id/deliverable", action: :mark_deliverable, as: :mark_deliverable # NTF-01
      end
      post :matches, on: :collection # POST keeps emails and phones out of URLs and access logs
      post :search, on: :collection # list results and the client picker (CLI-02); POST keeps search terms out of URLs
    end

    # Business management (with tabs for profile, hours, branding)
    resource :business, only: [ :new, :create, :edit, :update ] do
      post :switch, on: :collection
    end

    # Team (ACC-03)
    resource :team, only: :show, controller: "team"
    resources :invitations, only: :create do
      member do
        post :resend
        patch :revoke
      end
    end
    resources :members, only: :update do
      member do
        patch :deactivate
        patch :reactivate
      end
    end

    # Client links (PLT-12)
    resources :client_links, only: [] do
      member do
        get :preview
        patch :revoke
        post :reissue
      end
    end

    # Quotes (QTE-01)
    resources :quotes do
      get :preview, on: :member
      get :pdf, on: :member
      get :property_options, on: :collection
      resources :attachments, only: :destroy, controller: "quote_attachments"
      resource :send, only: %i[new create], controller: "quote_sends" # QTE-04
    end

    # "Send me a test email" from branding settings (NTF-01)
    resource :test_email, only: :create

    # Tax rates (CAT-04)
    resources :tax_rates, except: %i[show destroy] do
      member do
        patch :archive
        patch :restore
      end
    end

    # Service catalog (CAT-03)
    resource :catalog_presets, path: "catalog/starter", only: %i[show create] # CAT-05
    resources :catalog_items, path: "catalog", except: %i[show destroy] do
      member do
        patch :archive
        patch :restore
        patch :move
      end
      get :search, on: :collection
    end

    # Dashboard
    resources :dashboard, only: [ :index ]
    root "dashboard#index"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # UI kit reference (PLT-05). Development and test only.
  if Rails.env.local?
    get "styleguide", to: "styleguide#show"
    get "styleguide/client", to: "styleguide#client"
  end

  # Marketing homepage
  root "home#index"

  # Marketing pages
  get "pricing", to: "pricing#index"
  get "about", to: "about#index"
  get "terms", to: "legal#terms"
  get "privacy", to: "legal#privacy"

  # Contact page
  get "contact", to: "contact#index"
  post "contact", to: "contact#create"
end
