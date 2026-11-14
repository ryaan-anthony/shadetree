# Staff requests: after sign-in, resolve the current business from the session and verify
# it against the user's active memberships. Anything else falls back to the user's most
# recently joined active business. See ADR 0014.
module BusinessContext
  extend ActiveSupport::Concern

  included do
    before_action :set_current_business
    helper_method :current_business, :current_membership
  end

  private

  def set_current_business
    return unless current_user

    Current.user = current_user
    memberships = current_user.business_users.active.includes(:business)
    membership = memberships.find_by(business_id: session[:current_business_id]) if session[:current_business_id]
    membership ||= memberships.order(created_at: :desc).first

    session[:current_business_id] = membership&.business_id
    Current.membership = membership
    Current.business = membership&.business
  end

  def switch_business_to(business)
    session[:current_business_id] = business.id
    set_current_business
  end

  def current_business = Current.business
  def current_membership = Current.membership
end
