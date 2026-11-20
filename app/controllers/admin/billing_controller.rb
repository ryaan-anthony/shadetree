# BIL-04: the Owner's billing actions, all on Stripe's hosted pages: choosing a plan (Checkout,
# or the portal to confirm a switch), "Manage billing" (the customer portal) and the return from
# Checkout. Owners only (the billing permission); support viewing as a member can't open them.
class Admin::BillingController < Admin::BaseController
  impersonation :blocked
  requires_permission :billing

  rescue_from Stripe::StripeError, StripeGateway::NotConfigured, Billing::Checkout::Unavailable do |error|
    Rails.error.report(error, handled: true, context: { business_id: current_business.id })
    redirect_to admin_plan_path, alert: "Billing isn't available right now. Please try again in a few minutes, or contact us."
  end

  # POST: plan and interval chosen on Settings → Plan.
  def checkout
    plan = Plan.find_by(key: params[:plan].to_s)
    interval = Plan::INTERVALS.key?(params[:interval]) ? params[:interval] : "monthly"
    return redirect_to(admin_plan_path, alert: "That plan isn't available.") unless plan && (plan.public || plan == current_business.plan)

    redirect_to billing.choose(plan, interval), allow_other_host: true, status: :see_other
  end

  # POST: "Manage billing" or "Update payment method".
  def portal
    redirect_to billing.portal(flow: params[:flow] == "payment" ? :payment : nil), allow_other_host: true, status: :see_other
  end

  # GET: back from Checkout.
  def done
    subscription = billing.complete!(params[:session_id])
    if subscription&.live?
      redirect_to admin_plan_path, notice: "Thanks! You're on #{subscription.plan&.name || current_business.reload.plan.name} now."
    else
      redirect_to admin_plan_path, notice: "Your payment is being confirmed. Your plan changes as soon as it is."
    end
  end

  private

  def billing = Billing::Checkout.new(current_business, plan_url: admin_plan_url, return_url: admin_billing_done_url)
end
