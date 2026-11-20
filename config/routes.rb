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
  # ACC-06: signing out one of your other browsers, from the account page
  delete "users/browsers/:id", to: "users/browser_sessions#destroy", as: :user_browser_session

  # Team invitations (ACC-03)
  resources :invitations, only: :show, param: :token do
    member do
      post :accept
      post :sign_up
    end
  end

  # Client links (PLT-12): the only way clients reach documents.
  # CLI-03: each business's public request form.
  get "request/:handle", to: "public_requests#new", as: :public_request
  post "request/:handle", to: "public_requests#create"
  get "request/:handle/sent", to: "public_requests#sent", as: :public_request_sent

  get "c/:token", to: "client_links#show", as: :client_link
  post "c/:token/fresh", to: "client_links#request_fresh", as: :request_fresh_client_link
  post "c/:token/quote/update", to: "client/quotes#request_update", as: :request_quote_update
  get "c/:token/quote/files/:id", to: "client/document_files#show", as: :client_quote_file, defaults: { kind: "quote" }
  get "c/:token/invoice/files/:id", to: "client/document_files#show", as: :client_invoice_file, defaults: { kind: "invoice" } # PAY-02
  get "c/:token/invoice/pdf", to: "client/invoices#pdf", as: :client_invoice_pdf
  get "c/:token/quote/pdf", to: "client/quotes#pdf", as: :client_quote_pdf # QTE-03
  post "c/:token/quote/approve", to: "client/quotes#approve", as: :approve_client_quote # QTE-05
  post "c/:token/quote/decline", to: "client/quotes#decline", as: :decline_client_quote
  post "c/:token/quote/changes", to: "client/quotes#request_changes", as: :request_changes_client_quote

  # Admin routes
  # OPS-01: the operator console (ADR 0019). Non-operators get "not found".
  namespace :ops do
    root "dashboard#index"
    get "two-factor/setup", to: "two_factor#setup", as: :two_factor_setup
    post "two-factor/setup", to: "two_factor#enable"
    post "two-factor/recovery-codes", to: "two_factor#regenerate", as: :two_factor_recovery_codes
    resource :two_factor_verification, only: %i[new create], controller: "two_factor", path: "two-factor"
    resources :operators, only: %i[index create destroy]
    resources :audit_entries, only: :index, path: "audit-log"
    resources :businesses, only: %i[index show] do # OPS-02
      resources :notes, only: %i[create edit update destroy]
      resource :impersonation, only: :create # OPS-03: view the app as a member
      resource :suspension, only: %i[create destroy] # OPS-04
      resource :plan_overrides, only: %i[edit update], path: "overrides" # OPS-04: comped limits and features
      resource :deletion, only: %i[create update destroy] # OPS-04: schedule, expedite, cancel
    end
    resource :impersonation, only: %i[edit update destroy]
    resources :plans, only: %i[index edit update] # OPS-04
    resources :presets, only: %i[index edit update] # OPS-04: industry presets (CAT-05)
    resources :feature_flags, only: %i[index update], path: "flags", constraints: { id: /[a-z0-9_]+/ } # OPS-04: release flags (PLT-11)
    resources :users, only: :index do # OPS-02: lookup by email
      member do # OPS-04: sign-in help
        post :confirmation, to: "user_actions#confirmation"
        post :password_reset, to: "user_actions#password_reset"
        post :unlock, to: "user_actions#unlock"
      end
    end
    resources :contact_messages, only: %i[index show update destroy], path: "messages" do # MKT-02
      delete :erase, on: :member
    end
    resources :tickets, only: %i[index show] do # OPS-05: the support inbox
      member do
        patch :assign
        post :reply
        post :note
        patch :status
      end
      resources :files, only: :show, controller: "ticket_files" # screenshots, checked then redirected
    end
  end

  namespace :admin do
    # Clients (CLI-01)
    # Your data (INS-02): CSV downloads and the export log
    resources :data_exports, only: %i[index show create], path: "data" do
      get "download/:table", action: :download, on: :collection, as: :download, constraints: { table: /[a-z_]+/ }
    end

    # Client CSV import (CLI-06)
    resources :client_imports, only: %i[new create show edit update], path: "clients/imports" do
      get :template, on: :collection
      member do
        get :report
        post :undo
      end
    end
    resources :clients do
      member do
        patch :archive
        patch :restore
        get :picked
        get :timeline # CLI-05: older events
        patch "contact_methods/:contact_method_id/deliverable", action: :mark_deliverable, as: :mark_deliverable # NTF-01
      end
      post :matches, on: :collection # POST keeps emails and phones out of URLs and access logs
      post :search, on: :collection # list results and the client picker (CLI-02); POST keeps search terms out of URLs
      resources :notes, only: %i[create edit update], controller: "client_notes" # CLI-05
      resource :erasure, only: %i[new create], controller: "client_erasures" # INS-02
    end

    # Business settings (tabs for profile, documents, branding, request form; hours and taxes have their own)
    resource :business, only: [ :new, :create, :edit, :update ] do
      post :switch, on: :collection
      get :request_form_qr # CLI-03
    end

    # Settings → Automations (NTF-04)
    resources :automations, only: %i[index new create edit update destroy] do
      post :recipe, on: :collection
      patch :toggle, on: :member
    end

    # Settings → Messages (NTF-03): one per client-facing email kind
    resources :custom_message_templates, only: %i[new create edit update destroy], path: "messages/own" do
      post :preview, on: :collection
    end
    resources :message_templates, only: %i[index edit update destroy], param: :kind, path: "messages" do
      post :preview, on: :member
    end

    # Team (ACC-03)
    resource :team, only: :show, controller: "team"
    resources :roles, only: %i[index new create edit update destroy] do # ACC-07
      get :delete, on: :member
    end
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

    # Guided onboarding (ACC-05)
    get "setup/sample-quote", to: "onboarding#sample_quote", as: :sample_quote
    patch "setup/dismiss", to: "onboarding#dismiss", as: :dismiss_setup
    patch "setup/show", to: "onboarding#show", as: :show_setup
    patch "welcome/dismiss", to: "onboarding#dismiss_welcome", as: :dismiss_welcome

    # The request inbox (CLI-04)
    resources :service_requests, path: "requests", only: %i[index show new create] do
      member do
        patch :status
        post :quote
      end
      resources :notes, only: :create, controller: "service_request_notes"
    end

    # Quotes (QTE-01)
    resources :quotes do
      get :preview, on: :member
      get :pdf, on: :member
      get :property_options, on: :collection
      post :search, on: :collection # QTE-06: POST keeps client names out of URLs
      member do
        patch :archive
        patch :unarchive
        post :duplicate
        patch :extend_expiry
        post :revise
        patch :reprice # CAT-08
        get "revisions/:number", action: :revision, as: :revision, constraints: { number: /\d+/ }
      end
      resources :attachments, only: :destroy, controller: "quote_attachments"
      resource :send, only: %i[new create], controller: "quote_sends" # QTE-04
      resource :approval, only: :create, controller: "quote_approvals" # QTE-05: on the client's behalf
      resource :job, only: :create, controller: "quote_jobs" # JOB-01: an approved quote becomes a job
      resources :invoices, only: :create, controller: "quote_invoices" # PAY-01: an approved quote, billed
    end

    # Invoices (PAY-01)
    resources :invoices, only: %i[index new create show edit update destroy] do
      get :preview, on: :member # PAY-02
      get :pdf, on: :member
      resource :send, only: %i[new create], controller: "invoice_sends" # PAY-02
      resources :payments, only: %i[new create edit update destroy], controller: "invoice_payments" # PAY-05
      post :search, on: :collection # POST keeps client names out of URLs
      member do
        post :revise
        post :discard_revision
        patch :void
        patch :reprice # CAT-08
      end
      resources :attachments, only: :destroy, controller: "invoice_attachments"
    end

    # The team calendar (JOB-03)
    get "schedule", to: "schedule#show", as: :schedule
    get "schedule/visits/:id", to: "schedule#visit", as: :schedule_visit
    patch "schedule/visits/:id", to: "schedule#move", as: :schedule_move

    # The day view for the people going on visits (JOB-04): only their own visits.
    get "my-day", to: "my_day#show", as: :my_day
    resources :my_visits, only: :show, path: "my-day/visits", controller: "my_visits" do
      member do
        patch :start
        patch :complete
        patch :reopen
      end
      resources :notes, only: :create, controller: "my_visit_notes"
      resources :photos, only: %i[create destroy], controller: "my_visit_photos"
    end

    # Jobs (JOB-01)
    resources :jobs, only: %i[index show new create edit update] do
      post :search, on: :collection # POST keeps client names out of URLs
      resources :invoices, only: :create, controller: "job_invoices" # PAY-01: the job's work, billed
      member do
        patch :complete
        patch :cancel
        patch :reopen
      end
      # Visits (JOB-02)
      resources :visits, only: %i[new create edit update] do
        member do
          patch :cancel
          patch :restore
          patch :complete
        end
      end
    end

    # "Send me a test email" from branding settings (NTF-01)
    resource :test_email, only: :create

    # Team notifications (NTF-02): the notification center and each member's email choices
    resources :notifications, only: :index do
      collection do
        patch :read_all
        get :settings
        patch :settings, action: :update_settings
      end
      member do
        get :open # marks it read and goes to what it's about
        patch :read
      end
    end

    # Tax rates (CAT-04)
    resources :tax_rates, except: %i[show destroy] do
      member do
        patch :archive
        patch :restore
      end
    end

    # Business hours and closures (CAT-06)
    resource :hours, only: %i[show update], controller: "hours"
    resource :plan, only: :show, controller: "plans" # BIL-01
    # OPS-05: asking Shadetree for help
    resources :support_tickets, only: %i[index new create show], path: "help" do
      post :reply, on: :member
      resources :files, only: :show, controller: "support_ticket_files" # screenshots, checked then redirected
    end
    resources :closures, except: %i[index show]

    # Locations (CAT-07)
    resources :locations, except: %i[show destroy] do
      member do
        patch :archive
        patch :restore
      end
      patch "members/:member", on: :collection, action: :default_for, as: :member_default
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
  get "up/jobs" => "health#jobs", as: :job_health_check # PLT-10: for the external uptime check
  post "csp-reports" => "csp_reports#create", as: :csp_reports # PLT-13

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
  get "robots.txt", to: "seo#robots", as: :robots, format: false # MKT-04
  get "sitemap.xml", to: "seo#sitemap", as: :sitemap, defaults: { format: :xml }
  get "pricing", to: "pricing#index"
  get "about", to: "about#index"
  get "features", to: "features#index" # MKT-01
  # Legal and trust pages (MKT-03); /terms and /privacy are the short links sign-up uses.
  get "terms", to: "legal#show", defaults: { slug: "terms" }
  get "privacy", to: "legal#show", defaults: { slug: "privacy" }
  get "legal", to: "legal#index", as: :legal
  resource :legal_acceptance, only: %i[show create], path: "legal/accept", controller: "users/legal_acceptances"
  get "legal/:slug(/:version)", to: "legal#show", as: :legal_document, constraints: { slug: /[a-z-]+/, version: /\d{4}-\d{2}-\d{2}/ }

  # Contact page
  get "contact", to: "contact#index"
  post "contact", to: "contact#create"
  get "contact/sent", to: "contact#sent", as: :contact_sent # MKT-02
end
