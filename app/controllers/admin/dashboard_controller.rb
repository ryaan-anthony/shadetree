class Admin::DashboardController < Admin::BaseController
  skip_before_action :require_business_setup, only: [ :index ]

  def index
    # If user has no business, redirect to business creation
    unless current_user.has_business?
      redirect_to new_admin_business_path
      return
    end

    @business = current_business
    @setup_steps = setup_steps(@business)
  end

  private

  def setup_steps(business)
    [
      { title: "Add your contact details", text: "Clients see your phone and email on every quote.",
        done: business.phone.present? && business.email.present?, action: "Add details", path: edit_admin_business_path },
      { title: "Set your working hours", text: "Used for scheduling and online booking.",
        done: business.timezone.present? && business.timezone != "UTC", action: "Set hours", path: edit_admin_business_path(tab: "hours") },
      { title: "Upload your logo", text: "Your logo and colour brand every page your clients see.",
        done: business.logo_url.present?, action: "Add logo", path: edit_admin_business_path(tab: "branding") }
    ]
  end
end
