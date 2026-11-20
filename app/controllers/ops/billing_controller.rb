# OPS-04 (with BIL-05): comp a plan with an optional end date, extend (or give) a trial, and apply
# a Stripe coupon to a business's subscription. Each needs a reason and a recent code, is audited
# and written to the business's billing history; the plan is worked out again at once
# (Billing::PlanResolver). Comps and trials don't change what Stripe bills; a coupon does.
class Ops::BillingController < Ops::BaseController
  before_action :require_recent_verification
  before_action { @business = Business.find_by!(uid: params[:business_id].to_s) }
  before_action { redirect_back_to_business(alert: "Give a reason.") if reason.blank? }

  def comp
    plan = params[:plan].presence && Plan.find_by(key: params[:plan].to_s)
    ends_at = end_of(params[:ends_on])
    return redirect_back_to_business(alert: "Choose an end date in the future, or none.") if ends_at == false || ends_at&.past?

    previous = @business.comp_plan&.key
    resolve { @business.update!(comp_plan: plan, comp_ends_at: plan && ends_at) }
    history(plan ? "comped" : "comp_cleared", "plan" => plan&.name, "ends_on" => ends_at&.to_date&.iso8601)
    audit!("business.plan_comped", business: @business, reason:, from: previous, to: plan&.key, ends_on: ends_at&.to_date&.iso8601)
    redirect_back_to_business(notice: plan ? "#{@business.name} is comped #{plan.name}." : "The comp is removed.")
  end

  def trial
    ends_at = end_of(params[:ends_on])
    return redirect_back_to_business(alert: "Choose an end date in the future.") unless ends_at && ends_at.future?

    plan = @business.trial_plan || Plan.find_by(key: Billing.settings.trial_plan) || Plan.listed.reject(&:free?).last
    previous = @business.trial_ends_at
    resolve { @business.update!(trial_plan: plan, trial_ends_at: ends_at, trial_reminded_days: nil) }
    history("trial_extended", "plan" => plan.name, "ends_on" => ends_at.to_date.iso8601)
    audit!("business.trial_changed", business: @business, reason:, from: previous&.to_date&.iso8601, to: ends_at.to_date.iso8601)
    note = @business.billing_status == "trialing" ? "The #{plan.name} trial runs until #{ends_at.to_date.to_fs(:long)}." : "Trial saved; a subscription or comp takes precedence."
    redirect_back_to_business(notice: note)
  end

  def coupon
    code = params[:coupon].to_s.strip
    return redirect_back_to_business(alert: "Enter a Stripe coupon or promotion code id.") unless code.match?(/\A[A-Za-z0-9_-]{1,100}\z/)

    subscription = Tenancy.with_business(@business) { @business.subscription }
    return redirect_back_to_business(alert: "#{@business.name} has no subscription to apply it to.") unless subscription&.live?

    discount = code.start_with?("promo_") ? { promotion_code: code } : { coupon: code }
    Billing.gateway.update_subscription(subscription.stripe_subscription_id, discounts: [ discount ])
    history("coupon_applied", "coupon" => code)
    audit!("business.coupon_applied", business: @business, reason:, coupon: code)
    redirect_back_to_business(notice: "Coupon #{code} applied in Stripe.")
  rescue Stripe::StripeError, StripeGateway::NotConfigured => error
    redirect_back_to_business(alert: "Stripe refused it: #{error.message.to_s.first(200)}")
  end

  private

  def reason = params[:reason].to_s.strip.first(500)

  # The end of a date in the business's time zone; nil for none, false if it isn't a date.
  def end_of(value)
    return nil if value.blank?

    @business.time_zone.local(*Date.iso8601(value.to_s).then { [ _1.year, _1.month, _1.day ] }).end_of_day
  rescue Date::Error
    false
  end

  def resolve
    @business.with_lock do
      yield
      Billing::PlanResolver.apply!(@business)
    end
  end

  def history(kind, details) = Tenancy.with_business(@business) { BillingEvent.record!(kind, details: details.merge("reason" => reason)) }

  def redirect_back_to_business(**flash) = redirect_to(ops_business_path(@business, anchor: "billing-actions"), **flash)
end
