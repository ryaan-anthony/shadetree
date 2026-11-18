# QTE-05: tells an office team member (Owners and Admins) that a client approved, declined or
# asked for changes on a quote, or that a teammate recorded an approval. Sent through
# NotificationType.deliver (NTF-02) to the members who want it, one email each.
class QuoteActivityMailer < TeamMailer
  def responded
    @business = Business.find(params[:business_id])
    user = User.find(params[:user_id])
    Tenancy.with_business(@business) do
      @response = QuoteResponse.includes(:recorded_by, quote: :client).find(params[:response_id])
      @quote = @response.quote
      @who = @response.on_behalf? ? @response.recorded_by&.full_name || "A teammate" : @quote.client.display_name
      @url = preview_admin_quote_url(@quote)
      @total = @quote.total
    end
    mail to: user.email, subject: self.class.subject_for(@response, @who)
  end

  def self.subject_for(response, who)
    number = response.quote.number
    case response.kind
    when "approved" then response.on_behalf? ? "Quote #{number} marked approved by #{who}" : "#{who} approved quote #{number}"
    when "declined" then "#{who} declined quote #{number}"
    else "#{who} asked for changes to quote #{number}"
    end
  end
end
