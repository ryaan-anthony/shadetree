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
    # This session's choice, then the user's last choice on any device, then their newest
    # membership. Every candidate must be an active membership.
    membership = [ session[:current_business_id], current_user.last_business_id ].compact.uniq
                   .lazy.filter_map { |id| memberships.find_by(business_id: id) }.first
    membership ||= memberships.order(created_at: :desc, id: :desc).first
    note_lost_access(membership) if session[:current_business_id] && session[:current_business_id] != membership&.business_id

    session[:current_business_id] = membership&.business_id
    Current.membership = membership
    Current.business = membership&.business
    touch_last_active(membership)
  end

  def switch_business_to(business)
    session[:current_business_id] = business.id
    current_user.update_column(:last_business_id, business.id)
    set_current_business
  end

  # "Last active" on the team page, written at most every 10 minutes.
  def touch_last_active(membership)
    return unless membership && (membership.last_active_at.nil? || membership.last_active_at < 10.minutes.ago)

    membership.update_column(:last_active_at, Time.current)
  end

  # The business this session was using is gone (membership removed or deactivated).
  def note_lost_access(fallback)
    flash.now[:alert] = if fallback
      "You no longer have access to the business you were using, so you're now in #{fallback.business.name}."
    else
      "You no longer have access to the business you were using."
    end
    flash[:alert] = flash.now[:alert] unless request.get? && fallback
  end

  def current_business = Current.business
  def current_membership = Current.membership
end
