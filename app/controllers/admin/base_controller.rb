class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_confirmed_account
  before_action :require_business_setup
  layout "app"

  private

  def require_confirmed_account
    if current_user && !current_user.confirmed?
      flash[:alert] = "Please confirm your email address before accessing the admin area."
      redirect_to root_path
    end
  end

  def require_business_setup
    # Skip business check for business creation controller
    return if controller_name == "businesses"

    # If user has no business, show modal to create one on dashboard
    # The dashboard will handle showing the creation modal
    unless current_user.has_business?
      # For non-dashboard routes, redirect to dashboard which will show modal
      redirect_to admin_root_path unless controller_name == "dashboard"
    end
  end

  def require_admin_access
    # TODO: Implement proper admin authorization
    # For now, we'll allow all authenticated users
    # In production, you'd check for admin role or permissions
    redirect_to root_path unless user_signed_in?
  end

  def current_business
    @current_business ||= begin
      business = nil

      # Try to get business from session
      if session[:current_business_id]
        business = current_user.businesses.find_by(id: session[:current_business_id])
      end

      # If session business not found or not set, get default business
      unless business
        business = current_user.current_business
        # Set session to this business for consistency
        session[:current_business_id] = business.id if business
      end

      business
    end
  end
  helper_method :current_business
end
