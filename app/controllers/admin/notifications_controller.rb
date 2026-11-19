# NTF-02: a member's notifications in the current business, and which ones they get by email.
class Admin::NotificationsController < Admin::BaseController
  allow_any_member
  before_action :set_notification, only: %i[open read]

  def index
    @notifications = mine.recent.limit(Notification::LIST_SIZE).to_a
  end

  # Opening one marks it read. Turbo's hover prefetch is skipped so hovering doesn't count.
  def open
    @notification.mark_read! unless request.headers["X-Sec-Purpose"] == "prefetch" || impersonation # OPS-03: support looking isn't the member reading
    redirect_to @notification.path
  end

  def read
    @notification.mark_read!
    redirect_back_or_to admin_notifications_path
  end

  def read_all
    mine.unread.update_all(read_at: Time.current)
    redirect_to admin_notifications_path, notice: "All caught up."
  end

  # From an email's footer, ?business=<uid> opens that business's settings (when a member of it).
  def settings
    if params[:business].present? && params[:business] != current_business.uid
      membership = current_user.business_users.active.joins(:business).find_by(businesses: { uid: params[:business].to_s })
      switch_business_to(membership.business) if membership
    end
    @membership = current_membership
    @types = NotificationType.for(@membership)
  end

  # Email on or off per type; in-app notifications are always on.
  def update_settings
    @membership = current_membership
    chosen = Array(params[:email])
    @membership.update!(notification_emails: NotificationType.for(@membership).to_h { [ _1.kind, chosen.include?(_1.kind) ] })
    redirect_to settings_admin_notifications_path, notice: "Email choices saved."
  end

  private

  def mine = Notification.for_user(current_user)

  def set_notification = @notification = mine.find_by_param!(params[:id])
end
