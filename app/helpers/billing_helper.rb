# BIL-04: links for operators into Stripe's dashboard, in the mode the app's key is in.
module BillingHelper
  def stripe_dashboard_url(path) = "https://dashboard.stripe.com/#{"test/" unless Billing.live_mode?}#{path}"

  # BIL-01: a limit and what's used of it. A limit of none means the plan doesn't include it,
  # which "0 of 0" doesn't say.
  def plan_limit_usage(limit, used, plan)
    if limit.nil? then "#{used}, no limit"
    elsif limit.zero? then used.zero? ? "Not included on #{plan.name}" : "#{used}, not included on #{plan.name}"
    else "#{used} of #{limit}"
    end
  end
end
