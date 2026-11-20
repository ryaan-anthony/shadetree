# OPS-04: telling a business's owner it's been scheduled for deletion, that it was cancelled,
# and when it's gone. Given plain values, never the business, since it may be gone by the time
# the email is sent.
class BusinessDeletionMailer < ApplicationMailer
  # Not sent if, by sending time, the deletion was cancelled, brought forward or done.
  def scheduled
    @business_name, @first_name, @due_on, @suspended = params.values_at(:business_name, :first_name, :due_on, :suspended)
    due = Business.where(id: params[:business_id]).pick(:deletion_due_at)
    return unless due && due.to_date == @due_on

    @support = ContactMailer.support_address
    mail to: params[:email], subject: "#{@business_name} will be deleted on #{@due_on.to_fs(:long)}"
  end

  def cancelled
    @business_name, @first_name = params.values_at(:business_name, :first_name)
    mail to: params[:email], subject: "#{@business_name} won't be deleted"
  end

  # Sent after the business is gone, so it only has what was kept for it.
  def completed
    @business_name = params[:business_name]
    @first_name = params[:first_name]
    mail to: params[:email], subject: "#{@business_name} has been deleted"
  end

  # The owner's details for these emails, as plain values.
  def self.params_for(business)
    owner = business.owner
    { email: owner.email, first_name: owner.first_name, business_name: business.name, business_id: business.id,
      due_on: business.deletion_due_at&.to_date, suspended: business.suspended? }
  end
end
