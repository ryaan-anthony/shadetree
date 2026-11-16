class Admin::DashboardController < Admin::BaseController
  allow_any_member

  def index
    @business = current_business
    @checklist = SetupChecklist.new(@business, membership: Current.membership) # ACC-05
  end
end
