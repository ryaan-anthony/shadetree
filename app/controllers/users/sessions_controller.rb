class Users::SessionsController < Devise::SessionsController
  layout "marketing"
  rate_limit to: 20, within: 10.minutes, only: :create, with: -> { redirect_to new_user_session_path, alert: "Too many sign-in attempts. Try again in a few minutes." }
  # Devise skips authenticate_user! inside its own controllers unless forced.
  prepend_before_action -> { authenticate_user!(force: true) }, only: :destroy_others

  # POST /users/sign_out_everywhere — ends every other session and remember-me cookie,
  # keeping this one.
  def destroy_others
    current_user.sign_out_everywhere!
    bypass_sign_in(current_user)
    redirect_to edit_user_registration_path, notice: "Signed out of all other devices."
  end

  protected

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || (resource.has_business? ? admin_root_path : new_admin_business_path)
  end
end
