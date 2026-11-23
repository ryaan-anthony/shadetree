# The business's client email budget (EmailMessage::CLIENT_EMAILS_PER_HOUR): staff quote and
# invoice sends count against it at the controller (Rails' rate_limit, scope "client-emails"), and
# so does JOB-12's "On my way", which still updates the client's page when the email can't go.
module ClientEmailBudget
  extend self

  # Takes one email from the budget; false when the business is at its limit.
  def take(business, store: Rails.cache)
    count = store.increment("rate-limit:client-emails:#{business.id}", 1, expires_in: 1.hour)
    return false if count && count > EmailMessage::CLIENT_EMAILS_PER_HOUR

    !Tenancy.with_business(business) { EmailMessage.hourly_limit_reached? }
  end
end
