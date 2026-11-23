class Users::ConfirmationsController < Devise::ConfirmationsController
  public_page! # the link in the confirmation email (#378)
  # OPS-03: what support may do while viewing as a member
  impersonation :blocked # account settings
  layout "marketing"
  rate_limit to: 5, within: 10.minutes, only: %i[create resend], with: -> { redirect_to new_user_confirmation_path, alert: "Too many requests. Try again in a few minutes." }

  # GET /users/awaiting_confirmation
  def awaiting_confirmation
    @email = current_user&.email || params[:email]
  end

  # POST /users/confirmation/resend
  # Signed in: resend to the current user. Signed out: the same answer whether or not the
  # address has an account, so this can't be used to discover accounts.
  def resend
    if current_user
      current_user.send_confirmation_instructions unless current_user.confirmed?
      redirect_back_or_to admin_root_path, notice: "We've sent a new confirmation link to #{current_user.email}."
    else
      email = params[:email].to_s.strip.downcase
      user = User.find_by(email:) if email.present?
      user.send_confirmation_instructions if user && !user.confirmed?
      redirect_to awaiting_confirmation_users_confirmation_path(email: email.presence),
                  notice: "If that address has an unconfirmed account, a new link is on its way."
    end
  end

  protected

  def after_confirmation_path_for(_resource_name, resource)
    sign_in(resource) unless user_signed_in?
    flash[:notice] = "Your email is confirmed."
    resource.has_business? ? admin_root_path : new_admin_business_path
  end
end
