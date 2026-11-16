# ACC-05: the setup checklist's extras: a sample quote to preview (built in memory, never
# saved), dismissing the checklist, and dismissing a technician's welcome.
class Admin::OnboardingController < Admin::BaseController
  requires_permission :business_settings, only: %i[sample_quote dismiss]
  allow_any_member only: :dismiss_welcome

  # The client's quote page for a sample quote, with the business's branding.
  def sample_quote
    @business = current_business
    @document = SampleQuote.build(current_business)
    @preview = true
    @sample = true
    render "client_links/show", layout: "client"
  end

  def dismiss
    current_business.update!(onboarded_at: Time.current)
    redirect_to admin_root_path, notice: "Setup checklist hidden. Everything it pointed to is in the menu."
  end

  def dismiss_welcome
    Current.membership.update!(welcome_dismissed_at: Time.current)
    redirect_to admin_root_path
  end
end
