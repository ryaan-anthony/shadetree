# "Send me a test email" (NTF-01): the signed-in owner or admin gets a sample client email,
# to check branding, the sender name and that replies reach the business.
class Admin::TestEmailsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only # it would email the member
  requires_permission :business_settings
  rate_limit to: 3, within: 10.minutes, by: -> { current_user.id },
             with: -> { redirect_to edit_admin_business_path(tab: "branding"), alert: "That's a few test emails already. Try again in a few minutes." }

  def create
    ClientMailer.send_later(:test_message, business: current_business, to: current_user.email, kind: "test_message",
                                           related: current_business, recipient_name: current_user.first_name)
    redirect_to edit_admin_business_path(tab: "branding"), notice: "Test email sent to #{current_user.email}. It should arrive within a minute."
  end
end
