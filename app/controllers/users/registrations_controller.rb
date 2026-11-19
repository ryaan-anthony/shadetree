class Users::RegistrationsController < Devise::RegistrationsController
  layout -> { %w[edit update].include?(action_name) ? "application" : "marketing" } # the account page is for signed-in people
  before_action :configure_sign_up_params, only: :create
  before_action :configure_account_update_params, only: :update
  rate_limit to: 5, within: 10.minutes, only: :destroy, by: -> { current_user&.id || request.remote_ip },
             with: -> { redirect_to edit_user_registration_path(anchor: "delete-account"), alert: "Too many tries. Wait a few minutes and try again." }
  before_action :guard_sign_up, only: :create
  SIGN_UPS_PER_IP = { limit: 10, within: 10.minutes }.freeze

  # A new password signs out every other browser (Devise checks the password's salt); their
  # sessions are ended in the list too (ACC-06).
  def update
    super do |user|
      user.user_sessions.active.where.not(id: current_user_session&.id).update_all(revoked_at: Time.current) if user.errors.empty? && user.saved_change_to_encrypted_password?
    end
  end

  # ACC-06: deleting your own account, with your password. Blocked while you're the only Owner
  # of a business others depend on.
  def destroy
    unless resource.valid_password?(params[:current_password].to_s)
      return redirect_to(edit_user_registration_path(anchor: "delete-account"), alert: "That password didn't match. Your account wasn't deleted.")
    end

    email, first_name = resource.email, resource.first_name
    unless resource.delete_account!
      return redirect_to(edit_user_registration_path(anchor: "delete-account"), alert: "Your account wasn't deleted: you're the only Owner of a business others depend on.")
    end

    AccountMailer.with(email:, first_name:).deleted.deliver_later
    sign_out(resource_name)
    redirect_to root_path, notice: "Your account is deleted. We've sent a confirmation to #{email}."
  end

  protected

  # PLT-13 (AbuseProtection): bots that fill the hidden field get the home page and no account;
  # a form sent too fast, from elsewhere, or too often from one address comes back filled in.
  def guard_sign_up
    return redirect_to(root_path) if honeypot_filled?

    problem = form_guard_problem("sign-up")
    problem ||= "There have been a lot of sign-ups from your network. Try again in a few minutes." if too_many_attempts?("sign-up", **SIGN_UPS_PER_IP)
    return unless problem

    build_resource(sign_up_params)
    resource.errors.add(:base, problem)
    clean_up_passwords(resource)
    render :new, status: :unprocessable_content
  end

  def build_resource(hash = {})
    super
    resource.new_record_from_sign_up = true if action_name == "create"
    # MKT-01: the home page's "Start free" box passes the email along.
    resource.email = params[:email].to_s.strip.first(254) if action_name == "new" && params[:email].is_a?(String)
  end

  # Unconfirmed users are signed in straight away and go on to set up their business.
  def after_sign_up_path_for(_resource)
    Analytics.track("Sign-up Completed", request:) # MKT-04
    new_admin_business_path
  end

  def after_inactive_sign_up_path_for(resource)
    Analytics.track("Sign-up Completed", request:)
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
