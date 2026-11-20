# BIL-04: the Owner's billing actions, all on Stripe's hosted pages: choosing a plan (Checkout,
# or the portal to confirm a switch), "Manage billing" (the customer portal) and the return from
# Checkout. Owners only (the billing permission); support viewing as a member can't open them.
# A suspended business's Owner can still open the portal (to cancel), nothing else
# (Admin::BaseController#refuse_suspended_business).
class Admin::BillingController < Admin::BaseController
  impersonation :blocked
  requires_permission :billing

  CONFIRMING = "Your payment is being confirmed. Your plan will update in a minute or two."

  rescue_from(Billing::Checkout::NotOffered) { redirect_to admin_plan_path, alert: "That plan isn't available." }
  rescue_from Stripe::StripeError, StripeGateway::NotConfigured, Billing::Checkout::Unavailable do |error|
    Rails.error.report(error, handled: true, context: { business_id: current_business.id })
    redirect_to admin_plan_path, alert: "Billing isn't available right now. Please try again in a few minutes, or contact us."
  end

  # POST: plan and interval chosen on Settings → Plan.
  def checkout
    redirect_to billing.choose(Plan.find_by(key: params[:plan].to_s), params[:interval].to_s), allow_other_host: true, status: :see_other
  end

  # POST: "Manage billing" or "Update payment method".
  def portal
    redirect_to billing.portal(flow: params[:flow] == "payment" ? :payment : nil), allow_other_host: true, status: :see_other
  end

  # GET: back from Checkout. If the subscription can't be read yet, the webhook applies it; the
  # Owner is never told anything that suggests paying again.
  def done
    subscription = begin
      billing.complete!(params[:session_id])
    rescue Stripe::StripeError, StripeGateway::NotConfigured, Billing::SubscriptionSync::Mismatch => error
      Rails.error.report(error, handled: true, context: { business_id: current_business.id })
      nil
    end
    if subscription&.live?
      redirect_to admin_plan_path, notice: "Thanks! You're on #{subscription.plan&.name || current_business.reload.plan.name} now."
    else
      redirect_to admin_plan_path, notice: CONFIRMING
    end
  end

  private

  # Links Stripe sends the Owner back to: on APP_HOST when it's set (production), else this host.
  def url_options_for_stripe = ENV["APP_HOST"].present? ? { host: ENV["APP_HOST"], protocol: "https" } : {}

  def billing
    Billing::Checkout.new(current_business, plan_url: admin_plan_url(**url_options_for_stripe), return_url: admin_billing_done_url(**url_options_for_stripe))
  end
end
