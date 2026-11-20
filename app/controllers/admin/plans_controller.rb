# Settings → Plan (BIL-01): the business's plan, what it includes and how much is used, next to
# the other plans. Owners choose a plan, or manage billing, on Stripe's hosted pages (BIL-04,
# Admin::BillingController); Admins see the plan only.
class Admin::PlansController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only # billing and plans
  requires_permission :business_settings

  # PLT-13: this page's forms post to us and are redirected to Stripe's Checkout or portal.
  content_security_policy do |policy|
    policy.form_action :self, "https://checkout.stripe.com", "https://billing.stripe.com"
  end

  def show
    @business = current_business
    @entitlements = @business.entitlements
    # A hidden plan the business is on still shows, in its place.
    @plans = (Plan.listed.to_a | [ @business.plan ]).sort_by { [ _1.position, _1.id ] }
    @subscription = Tenancy.with_business(@business) { @business.subscription }
  end
end
