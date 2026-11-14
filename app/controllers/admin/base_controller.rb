class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_confirmed_account
  include BusinessContext
  before_action :require_business_setup
  layout "app"

  private

  def require_confirmed_account
    if current_user && !current_user.confirmed?
      flash[:alert] = "Please confirm your email address before accessing the admin area."
      redirect_to root_path
    end
  end

  # Staff pages need a current business; without one, send the user to create it.
  def require_business_setup
    redirect_to new_admin_business_path unless current_business
  end
end
