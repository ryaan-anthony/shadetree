class Admin::DashboardController < Admin::BaseController
  allow_any_member

  # Members who don't work in the office (technicians) land on their day view (JOB-04).
  def index
    return redirect_to(admin_my_day_path) unless can?(:office) || can?(:business_settings)

    @business = current_business
    @checklist = SetupChecklist.new(@business, membership: Current.membership) # ACC-05
  end
end
