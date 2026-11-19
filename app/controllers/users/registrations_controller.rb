class Users::RegistrationsController < Devise::RegistrationsController
  layout "marketing"
  before_action :configure_sign_up_params, only: :create
  before_action :configure_account_update_params, only: :update
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to new_user_registration_path, alert: "Too many attempts. Try again in a few minutes." }

  protected

  def build_resource(hash = {})
    super
    resource.new_record_from_sign_up = true if action_name == "create"
    # MKT-01: the home page's "Start free" box passes the email along.
    resource.email = params[:email].to_s.strip.first(254) if action_name == "new" && params[:email].is_a?(String)
  end

  # Unconfirmed users are signed in straight away and go on to set up their business.
  def after_sign_up_path_for(_resource)
    new_admin_business_path
  end

  def after_inactive_sign_up_path_for(resource)
    awaiting_confirmation_users_confirmation_path(email: resource.email)
  end

  def after_update_path_for(_resource)
    edit_user_registration_path
  end

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :first_name, :last_name, :terms_of_service ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :first_name, :last_name ])
  end
end
