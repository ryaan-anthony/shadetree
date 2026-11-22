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

  # #289: what "1 of 5" means, where it's shown: whose quotes, which period.
  #   "1 of your 5 free quotes this month"
  #   "12 of your 30 Starter quotes this billing period"
  def quote_allowance(entitlements, used: entitlements.used(:quotes_sent))
    limit = entitlements.limit(:quotes_sent) or return
    period = entitlements.period.billing_cycle? ? "this billing period" : "this month"
    plan = entitlements.plan
    "#{used} of your #{limit} #{plan.free? ? "free" : plan.name} quotes #{period}"
  end
end
