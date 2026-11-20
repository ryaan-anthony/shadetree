# Settings → Payments (PAY-03): the business's own Stripe account, through Stripe's hosted
# onboarding. Owners connect, finish or fix setup, and disconnect; Admins see the status.
# Stripe sends the owner back to #returned (finished or left part-way) or #resume (the one-time
# link expired or was used: a fresh one). The status is fetched on return and kept in sync by
# Stripe's notifications (Webhooks::StripeConnectController).
class Admin::PaymentAccountsController < Admin::BaseController
  # OPS-03: payment settings are never opened while viewing as a member
  impersonation :blocked
  requires_permission :business_settings
  requires_permission :billing, only: %i[create resume returned destroy]

  # The forms here post to us and are redirected to Stripe's onboarding (PLT-13).
  content_security_policy { |policy| policy.form_action :self, "https://connect.stripe.com" }

  before_action :set_account

  def show
    @gateway = PaymentGateway.current
  end

  # Starts onboarding: a Standard account the first time, then Stripe's hosted pages.
  def create
    return redirect_to(admin_payment_account_path, alert: "Online payments aren't available yet.") unless gateway.configured?

    @account ||= PaymentAccount.create!(account_id: gateway.create_account(business_uid: current_business.uid).fetch("id"), connected_by: current_user)
    send_to_onboarding
  rescue PaymentGateway::Error => error
    stripe_problem(error)
  end

  def resume
    return redirect_to(admin_payment_account_path) unless @account

    send_to_onboarding
  rescue PaymentGateway::Error => error
    stripe_problem(error)
  end

  def returned
    return redirect_to(admin_payment_account_path) unless @account

    @account.sync!(gateway.retrieve_account(@account.account_id))
    notice = case @account.status
    when "active" then "You're set up to take card payments."
    when "pending_verification" then "Thanks. Stripe is checking your details; that's usually quick."
    when "onboarding_incomplete" then "Setup isn't finished yet. Continue whenever you're ready."
    else "Stripe needs a little more from you before payments can start."
    end
    redirect_to admin_payment_account_path, notice:
  rescue PaymentGateway::Error => error
    stripe_problem(error)
  end

  def destroy
    return redirect_to(admin_payment_account_path) unless @account

    @account.disconnect!(reason: "owner", by: current_user, gateway:)
    redirect_to admin_payment_account_path, notice: "Stripe is disconnected. Clients can't pay online until you connect again. Your Stripe account and its money are untouched."
  rescue PaymentGateway::Error => error
    stripe_problem(error)
  end

  private

  def gateway = PaymentGateway.current

  def set_account = @account = PaymentAccount.current

  def send_to_onboarding
    url = gateway.onboarding_url(@account.account_id, return_url: return_admin_payment_account_url, refresh_url: resume_admin_payment_account_url)
    redirect_to url, allow_other_host: true, status: :see_other
  end

  def stripe_problem(error)
    Rails.error.report(error, handled: true, context: { business_id: current_business.id })
    redirect_to admin_payment_account_path, alert: "Stripe didn't respond as expected, so nothing changed. Try again in a minute."
  end
end
