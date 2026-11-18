# NTF-02: the email for a team notification that has no email of its own: its title, detail and
# a link. Notifications with richer emails (new requests, quote responses) pass their own.
class NotificationMailer < TeamMailer
  def notice
    business = Business.find(params[:business_id])
    @notification = Tenancy.with_business(business) { Notification.includes(:user).find(params[:notification_id]) }
    @url = "#{root_url.chomp("/")}#{@notification.path}"
    mail to: @notification.user.email, subject: @notification.title
  end
end
