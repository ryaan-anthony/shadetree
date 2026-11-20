# BIL-04: links for operators into Stripe's dashboard, in the mode the app's key is in.
module BillingHelper
  def stripe_dashboard_url(path) = "https://dashboard.stripe.com/#{"test/" unless Billing.live_mode?}#{path}"
end
