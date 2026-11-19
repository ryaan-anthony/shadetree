# ACC-06: confirming an account deletion, sent to the address the account had (it's gone from
# the account itself by the time this goes out).
class AccountMailer < ApplicationMailer
  def deleted
    @first_name = params[:first_name]
    mail to: params[:email], subject: "Your Shadetree account is deleted"
  end
end
