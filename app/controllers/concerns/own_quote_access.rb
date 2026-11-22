# QTE-07: who reaches a quote. Office staff reach every quote; members who can quote requests
# assigned to them (quote_requests) reach only the drafts they made from a request, until
# they're sent. Anyone else is refused; another member's quote is "not found".
module OwnQuoteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :own_quotes_only?
  end

  private

  # Not office staff: limited to their own drafts from requests.
  def own_quotes_only? = !can?(:office)

  # The quotes this member may open, or nil (after refusing) when they may open none.
  def reachable_quotes
    return Quote.all unless own_quotes_only?
    return deny!(:office, "no quote access") && nil unless can?(:quote_requests)

    Quote.own_drafts_for(current_user)
  end
end
