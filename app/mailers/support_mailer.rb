# OPS-05: Shadetree support writing to a member about a ticket. Once inbound email is on
# (InboundEmailIngress.replies_by_email?), Reply-To is the member's signed reply address for the
# ticket, the only way an answer by email threads back in (SupportMail); until then it's the
# support address and the email says to reply in Shadetree.
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
    @reply_by_email = InboundEmailIngress.replies_by_email?
    mail to: @user.email, from: email_address_with_name(Mail::Address.new(default_params[:from]).address, "Shadetree Support"),
         reply_to: @reply_by_email ? SupportMail.reply_address(@ticket, @user) : self.class.support_address, subject: SupportMail.subject_for(@ticket)
  end

  private

  def custom_message_id = (SupportMail.message_id_for(@ticket, @message) if @ticket)
end
