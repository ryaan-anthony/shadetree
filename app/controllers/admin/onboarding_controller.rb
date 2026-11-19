# ACC-05: the setup checklist's extras: a sample quote to preview (built in memory, never
# saved), dismissing the checklist, and dismissing a technician's welcome.
class Admin::OnboardingController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :business_settings, only: %i[sample_quote dismiss show]
  allow_any_member only: :dismiss_welcome

  # The client's quote page for a sample quote, with the business's branding.
  def sample_quote
    @business = current_business
    @document = SampleQuote.build(current_business)
    @preview = true
    @sample = true
    render "client_links/show", layout: "client"
  end

  # Hides the checklist for this member only; "Show setup checklist" on the dashboard undoes it.
  def dismiss
    Current.membership.update!(setup_hidden_at: Time.current)
    redirect_to admin_root_path, notice: "Setup checklist hidden. You can show it again from the bottom of this page."
  end

  def show
    Current.membership.update!(setup_hidden_at: nil)
    redirect_to admin_root_path
  end

  def dismiss_welcome
    Current.membership.update!(welcome_dismissed_at: Time.current)
    redirect_to((can?(:office) || can?(:business_settings)) ? admin_root_path : admin_my_day_path)
  end
end
