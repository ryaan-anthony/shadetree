class Users::RegistrationsController < Devise::RegistrationsController
  layout 'marketing'

  # GET /resource/sign_up
  # def new
  #   super
  # end

  # POST /resource
  # def create
  #   super
  # end

  protected

  # Override after_sign_up_path_for to redirect to awaiting confirmation
  def after_sign_up_path_for(resource)
    awaiting_confirmation_users_confirmation_path(email: resource.email)
  end

  # Override after_inactive_sign_up_path_for to redirect to awaiting confirmation
  def after_inactive_sign_up_path_for(resource)
    awaiting_confirmation_users_confirmation_path(email: resource.email)
  end
  # cancel oauth signing in/up in the middle of the process,
  # removing all OAuth session data.
  # def cancel
  #   super
  # end

  protected

  # If you have extra params to permit, append them to the sanitizer.
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [:account_tier])
  end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_account_update_params
  #   devise_parameter_sanitizer.permit(:account_update, keys: [:attribute])
  # end

  # The path used after sign up.
  # def after_sign_up_path_for(resource)
  #   super(resource)
  # end

  # The path used after sign up for inactive accounts.
  # def after_inactive_sign_up_path_for(resource)
  #   super(resource)
  # end
end
