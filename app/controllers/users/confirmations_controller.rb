class Users::ConfirmationsController < Devise::ConfirmationsController
  layout "marketing"

  # GET /users/awaiting_confirmation
  def awaiting_confirmation
    @email = params[:email] || current_user&.email
  end

  # POST /users/confirmation/resend
  def resend
    email = params[:email]

    if email.blank?
      flash[:alert] = "Please provide an email address."
      redirect_to awaiting_confirmation_users_confirmation_path and return
    end

    user = User.find_by(email: email)

    if user.nil?
      flash[:alert] = "We couldn't find an account with that email address."
      redirect_to awaiting_confirmation_users_confirmation_path(email: email)
    elsif user.confirmed?
      flash[:notice] = "Your email is already confirmed. Please sign in."
      redirect_to new_user_session_path
    else
      user.send_confirmation_instructions
      flash[:notice] = "Confirmation email has been resent to #{email}. Please check your inbox."
      redirect_to awaiting_confirmation_users_confirmation_path(email: email)
    end
  end

  protected

  def after_confirmation_path_for(resource_name, resource)
    sign_in(resource)
    flash[:notice] = "Your email has been confirmed! Welcome to Shadetree."
    admin_root_path
  end
end
