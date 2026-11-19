# MKT-02: contact-form messages. The team's copy goes to the support address with reply-to set
# to the sender; the sender's confirmation doesn't repeat what they wrote (so the form can't be
# used to send someone else a message).
class ContactMailer < ApplicationMailer
  def self.support_address = ENV.fetch("SUPPORT_EMAIL", "support@getshadetree.com")

  def received
    @message = params[:message]
    mail to: self.class.support_address, reply_to: email_address_with_name(@message.email, @message.name),
         subject: "Contact form: #{@message.name}#{" (#{@message.business_name})" if @message.business_name}"
  end

  def confirmation
    @message = params[:message]
    mail to: @message.email, subject: "We got your message"
  end
end
