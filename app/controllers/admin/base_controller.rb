class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  include BusinessContext
  include ConfirmedSender
  before_action :require_business_setup
  include Authorization # after setup, so users without a business are sent to create one
  layout "app"

  private

  # Staff pages need a current business; without one, send the user to create it.
  def require_business_setup
    redirect_to new_admin_business_path unless current_business
  end
end
