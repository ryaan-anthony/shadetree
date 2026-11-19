# OPS-04: telling a business's owner it's been scheduled for deletion, and when it's gone.
class BusinessDeletionMailer < ApplicationMailer
  def scheduled
    @business = params[:business]
    @owner = @business.owner
    @support = ContactMailer.support_address
    mail to: @owner.email, subject: "#{@business.name} will be deleted on #{@business.deletion_due_at.to_date.to_fs(:long)}"
  end

  # Sent after the business is gone, so it only has what was kept for it.
  def completed
    @business_name = params[:business_name]
    @first_name = params[:first_name]
    mail to: params[:email], subject: "#{@business_name} has been deleted"
  end
end
