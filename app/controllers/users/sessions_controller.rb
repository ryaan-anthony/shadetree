class Users::SessionsController < Devise::SessionsController
  layout "marketing"

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  protected

  # Redirect confirmed users to admin dashboard after sign in
  def after_sign_in_path_for(resource)
    if resource.confirmed?
      admin_root_path
    else
      # Sign out the user and redirect to awaiting confirmation page
      sign_out(resource)
      flash[:alert] = "Please confirm your email address before signing in."
      awaiting_confirmation_users_confirmation_path(email: resource.email)
    end
  end
end
