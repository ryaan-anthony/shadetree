# Development previews of client-facing email (NTF-01) at /rails/mailers. Each message type in
# EmailCatalog gets a preview here when its spec adds it.
class ClientMailerPreview < ActionMailer::Preview
  # The branded layout with the demo business (bin/rails db:seed).
  def test_message
    business = Business.order(:id).first
    ClientMailer.with(business_id: business.id, to: "dana@example.com", recipient_name: "Dana").test_message
  end
end

# QTE-04: the quote email, for the newest quote with lines (bin/rails db:seed makes one).
class QuoteMailerPreview < ActionMailer::Preview
  def sent
    quote = Tenancy.across_businesses(reason: "mailer preview") { Quote.joins(:line_items).order(:id).last }
    Tenancy.with_business(quote.business) do
      link = quote.client_link!
      QuoteMailer.with(business_id: quote.business_id, to: "maria@example.com", quote_id: quote.id, link_id: link.id,
                       subject: QuoteMailer.default_subject(quote), message: "Hi Maria,\n\nHere's the quote we talked about.").sent
    end
  end
end

# QTE-05: the client's approval confirmation and the team's notice, for the newest approved
# quote (bin/rails db:seed makes one).
class QuoteApprovalMailerPreview < ActionMailer::Preview
  def approved
    quote = approved_quote
    QuoteMailer.with(business_id: quote.business_id, to: "maria@example.com", quote_id: quote.id).approved
  end

  def team_notice
    quote = approved_quote
    response = Tenancy.with_business(quote.business) { quote.approval }
    QuoteActivityMailer.with(business_id: quote.business_id, response_id: response.id, user_id: quote.business.users.first.id).responded
  end

  private

  def approved_quote = Tenancy.across_businesses(reason: "mailer preview") { Quote.where(status: "approved").order(:id).last }
end
