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

  # #289: what "1 of 5" means, where it's shown: whose quotes, which period. nil without a limit
  # (or with none included). count: false leaves the number out, for beside a big figure.
  #   "Used 1 of your 5 free quotes this month"
  #   "Used 12 of your 30 Starter quotes this billing period (trial)"
  #   "You've used all 5 free quotes this month"
  #   count: false => "Of your 5 free quotes this month" / "All 5 free quotes used this month"
  def quote_allowance(entitlements, used: entitlements.used(:quotes_sent), count: true)
    limit = entitlements.limit(:quotes_sent)
    return if limit.nil? || limit.zero?

    plan = entitlements.plan
    quotes = "#{limit} #{plan.free? ? "free" : plan.name} quotes"
    period = entitlements.period.billing_cycle? ? "this billing period" : "this month"
    trial = " (trial)" if entitlements.business.billing_status == "trialing"
    text = if used >= limit then count ? "You've used all #{quotes} #{period}" : "All #{quotes} used #{period}"
    else count ? "Used #{used} of your #{quotes} #{period}" : "Of your #{quotes} #{period}"
    end
    "#{text}#{trial}"
  end
end
