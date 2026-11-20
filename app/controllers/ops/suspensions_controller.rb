# OPS-04: suspending and reactivating a business, each with a reason and a fresh code, audited.
# Suspension doesn't touch billing; the operator decides that per case (approved).
class Ops::SuspensionsController < Ops::BaseController
  before_action :require_recent_verification
  before_action :set_business

  def create
    return back(alert: "Give a reason for suspending.") if reason.blank?
    return back(alert: "Only an active business can be suspended.") unless @business.active?

    @business.suspend!(reason:)
    audit!("business.suspended", business: @business, reason:)
    back(notice: "#{@business.name} is suspended. Its members see a contact-support page and client links show as unavailable.")
  end

  def destroy
    return back(alert: "Give a reason for reactivating.") if reason.blank?
    return back(alert: "This business isn't suspended.") unless @business.suspended?

    @business.reactivate!
    audit!("business.reactivated", business: @business, reason:)
    back(notice: "#{@business.name} is active again.")
  end

  private

  def set_business = @business = Business.find_by!(uid: params[:business_id].to_s)
  def reason = params[:reason].to_s.strip.first(500)
  def back(**flash) = redirect_to(ops_business_path(@business, anchor: "account-actions"), **flash)
end
