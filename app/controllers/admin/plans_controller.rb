# Settings → Plan (BIL-01): the business's plan, what it includes and how much is used, next to
# the other plans. Changing plan comes with BIL-04.
class Admin::PlansController < Admin::BaseController
  requires_permission :business_settings

  def show
    @business = current_business
    @entitlements = @business.entitlements
    @plans = Plan.listed.to_a
    @plans |= [ @business.plan ] # a hidden plan the business is on still shows
  end
end
