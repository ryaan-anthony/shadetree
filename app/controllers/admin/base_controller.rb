class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_business_setup
  layout 'admin'

  private

  def require_business_setup
    # Skip business setup check for the onboarding controller itself
    return if controller_name == 'business_onboarding'

    unless current_user.has_business?
      redirect_to new_admin_business_onboarding_path
      return
    end
  end

  def require_admin_access
    # TODO: Implement proper admin authorization
    # For now, we'll allow all authenticated users
    # In production, you'd check for admin role or permissions
    redirect_to root_path unless user_signed_in?
  end

  def current_business
    @current_business ||= current_user.current_business
  end
  helper_method :current_business
end
