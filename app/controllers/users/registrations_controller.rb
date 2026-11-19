class Users::RegistrationsController < Devise::RegistrationsController
  layout -> { %w[edit update].include?(action_name) ? "application" : "marketing" } # the account page is for signed-in people
  before_action :configure_sign_up_params, only: :create
  before_action :configure_account_update_params, only: :update
  rate_limit to: 10, within: 10.minutes, only: :create, with: -> { redirect_to new_user_registration_path, alert: "Too many attempts. Try again in a few minutes." }

  # A new password signs out every other browser (Devise checks the password's salt); their
  # sessions are ended in the list too (ACC-06).
  def update
    super do |user|
      user.user_sessions.active.where.not(id: current_user_session&.id).update_all(revoked_at: Time.current) if user.errors.empty? && user.saved_change_to_encrypted_password?
    end
  end

  protected

  def build_resource(hash = {})
    super
    resource.new_record_from_sign_up = true if action_name == "create"
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
