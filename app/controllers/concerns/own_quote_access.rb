# QTE-07: who reaches a quote. Office staff reach every quote; members who can quote requests
# assigned to them (quote_requests) reach only the drafts they made from a request, until
# they're sent. Anyone else is refused; another member's quote is "not found".
module OwnQuoteAccess
  extend ActiveSupport::Concern

  included do
    helper_method :own_quotes_only?, :without_review_check
  end

  private

  # QTE-08: for a member who doesn't send their own quotes, whether this draft of theirs can go
  # without review (nil when that doesn't apply to them or it).
  def without_review_check(quote)
    return unless SendWithoutReview.applies_to?(quote, Current.membership)

    (@without_review_checks ||= {})[quote.id] ||= SendWithoutReview.new(quote)
  end

  # Not office staff: limited to their own drafts from requests.
  def own_quotes_only? = !can?(:office)

  # The quotes this member may open, or nil (after refusing) when they may open none.
  def reachable_quotes
    return Quote.all unless own_quotes_only?
    return deny!(:office, "no quote access") && nil unless can?(:quote_requests)

    Quote.own_drafts_for(current_user)
  end
end
