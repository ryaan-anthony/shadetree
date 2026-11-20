# OPS-04: scheduling a business for permanent deletion (typing its name to confirm), and
# cancelling or expediting it during the waiting period. Each needs a reason and a fresh code,
# and is audited; the owner is emailed when it's scheduled and when it's done.
class Ops::DeletionsController < Ops::BaseController
  WAITING_PERIOD = 30.days

  before_action :require_recent_verification
  before_action :set_business

  def create
    return back(alert: "This business is already scheduled for deletion.") if @business.deletion_due_at
    return unless confirmed?

    @business.update_columns(deletion_scheduled_at: Time.current, deletion_due_at: WAITING_PERIOD.from_now, updated_at: Time.current)
    audit!("business.deletion_scheduled", business: @business, reason:, due: @business.deletion_due_at.iso8601)
    BusinessDeletionMailer.with(**BusinessDeletionMailer.params_for(@business)).scheduled.deliver_later unless @business.owner.deleted?
    back(notice: "#{@business.name} will be deleted on #{@business.deletion_due_at.to_date.to_fs(:long)}. The owner has been emailed.#{stripe_note(cancel: true)}")
  end

  # Delete now, without waiting (a privacy request, say).
  def update
    return back(alert: "Schedule the deletion first.") unless @business.deletion_due_at
    return unless confirmed?

    @business.update_columns(deletion_due_at: Time.current, updated_at: Time.current)
    audit!("business.deletion_expedited", business: @business, reason:)
    DeleteScheduledBusinessesJob.perform_later(@business.id)
    redirect_to ops_businesses_path, notice: "#{@business.name} is being deleted now."
  end

  def destroy
    return back(alert: "This business isn't scheduled for deletion.") unless @business.deletion_due_at
    return back(alert: "Give a reason for cancelling.") if reason.blank?

    @business.update_columns(deletion_scheduled_at: nil, deletion_due_at: nil, updated_at: Time.current)
    audit!("business.deletion_cancelled", business: @business, reason:)
    BusinessDeletionMailer.with(**BusinessDeletionMailer.params_for(@business)).cancelled.deliver_later unless @business.owner.deleted?
    back(notice: "Deletion cancelled. #{@business.name} stays.#{stripe_note(cancel: false)}")
  end

  private

  def set_business = @business = Business.find_by!(uid: params[:business_id].to_s)
  def reason = params[:reason].to_s.strip.first(500)
  def back(**flash) = redirect_to(ops_business_path(@business, anchor: "deletion"), **flash)

  # BIL-04: the subscription stops renewing while the deletion waits, and renews again if it's
  # cancelled. If Stripe can't be reached, the operator is told to do it there.
  def stripe_note(cancel:)
    changed = Billing.cancel_for_deletion!(@business, cancel:)
    if changed.empty? then ""
    else cancel ? " Its subscription won't renew." : " Its subscription renews again."
    end
  rescue Stripe::StripeError, StripeGateway::NotConfigured => error
    Rails.error.report(error, handled: true, context: { business_id: @business.id })
    " Stripe couldn't be reached: #{cancel ? "set the subscription to cancel" : "resume the subscription"} in Stripe."
  end

  def confirmed?
    return true if reason.present? && params[:confirm_name].to_s.strip == @business.name

    back(alert: reason.blank? ? "Give a reason." : "Type the business's name exactly to confirm.")
    false
  end
end
