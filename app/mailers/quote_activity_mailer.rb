# QTE-05: tells the business's office team (Owners and Admins) that a client approved,
# declined or asked for changes on a quote, or that a teammate recorded an approval. One email
# per member, so addresses aren't shared. In-app notifications and per-member choices come with
# NTF-02.
class QuoteActivityMailer < ApplicationMailer
  helper FormattingHelper

  # The members to tell: active, confirmed, allowed to see quotes, not the person who did it.
  def self.recipients(response)
    roles = Permissions.roles_with(:office)
    response.business.business_users.active.where(role: roles).includes(:user).map(&:user)
            .select(&:confirmed?).reject { _1.id == response.recorded_by_id }
  end

  def self.deliver_later_for(response)
    recipients(response).each { with(response_id: response.id, business_id: response.business_id, user_id: _1.id).responded.deliver_later }
  end

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
