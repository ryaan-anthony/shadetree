# OPS-05: Shadetree support writing to the member who opened a ticket. Replies go to the support
# address; the ticket's reference is in the subject and the Message-ID, so an answer by email
# threads back into the ticket (SupportMail).
class SupportMailer < TeamMailer
  def self.support_address = ContactMailer.support_address

  # A reply from support (or the notice that a ticket was closed), with its text.
  def reply
    @business = Business.find(params[:business_id])
    Tenancy.with_business(@business) do
      @message = SupportMessage.includes(:support_ticket).find(params[:message_id])
      @ticket = @message.support_ticket
    end
    @user = params[:user]
    @url = admin_support_ticket_url(@ticket)
    mail to: @user.email, from: email_address_with_name(Mail::Address.new(default_params[:from]).address, "Shadetree Support"),
         reply_to: self.class.support_address, subject: SupportMail.subject_for(@ticket)
  end

  private

  def custom_message_id = (SupportMail.message_id_for(@ticket, @message) if @ticket)
end
