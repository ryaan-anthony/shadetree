# Settings → Plan (BIL-01): the business's plan, what it includes and how much is used, next to
# the other plans. Changing plan comes with BIL-04.
class Admin::PlansController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only # billing and plans
  requires_permission :business_settings

  def show
    @business = current_business
    @entitlements = @business.entitlements
    # A hidden plan the business is on still shows, in its place.
    @plans = (Plan.listed.to_a | [ @business.plan ]).sort_by { [ _1.position, _1.id ] }
  end
end
