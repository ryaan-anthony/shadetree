module QuotesHelper
  # QTE-08: whether a technician can send this draft without review right now: it qualifies, the
  # plan's quotes aren't used up (no grace send), and their email is confirmed (ACC-01).
  def send_without_review_now?(quote)
    check = without_review_check(quote)
    check&.qualifies? && current_business.entitlements.can_send_new_quote? && current_user.can_send_to_clients?
  end

  # Where a quote opens for staff: the builder for a draft, its own page once it's sent (QTE-06).
  def staff_quote_path(quote) = quote.editable? ? edit_admin_quote_path(quote) : admin_quote_path(quote)

  # The quote's status for staff (PLT-17's map): expiry counts, and archived quotes say so.
  def quote_status_badge(quote)
    key = quote.expired? ? "expired" : quote.status
    safe_join([ status_badge(:quote, key), (status_badge(:quote, "archived", dot: false) if quote.archived?) ].compact, " ")
  end

  # The list's date: when it was sent, or for a draft when it was last changed.
  def quote_list_date(quote)
    return local_date(quote.sent_at.in_time_zone(current_business.time_zone).to_date) if quote.sent_at

    safe_join([ "Updated ", local_date_ago(quote.updated_at) ])
  end

  # The client's reason, for a declined quote (from preloaded responses).
  def quote_decline_reason(quote)
    quote.responses.reverse.find { _1.kind == "declined" }&.message if quote.status == "declined"
  end

  # "Not opened" / "Viewed 3×" for a sent quote waiting on the client (QTE-06: an indicator, not a status).
  def quote_viewed_note(quote, views)
    return unless quote.sent? && !quote.expired?

    views.to_i.zero? ? "Not opened" : "Viewed #{views}×"
  end
end
