class Admin::DashboardController < Admin::BaseController
  allow_any_member
  def index
    @business = current_business
    @setup_steps = setup_steps(@business)
  end

  private

  def setup_steps(business)
    [
      { title: "Add your contact details", text: "Clients see your phone and email on every quote.",
        done: business.phone.present? && business.email.present?, action: "Add details", path: edit_admin_business_path },
      { title: "Add your address and time zone", text: "Used on documents, for scheduling and due dates.",
        done: business.address_line1.present? && business.timezone.present?, action: "Add address", path: edit_admin_business_path },
      { title: "Add your services", text: "Start from common services for your industry and set your prices.",
        done: CatalogItem.exists?, action: "Add services", path: admin_catalog_presets_path },
      { title: "Upload your logo", text: "Your logo and colour brand every page your clients see.",
        done: business.logo_url.present?, action: "Add logo", path: edit_admin_business_path(tab: "branding") }
    ]
  end
end
