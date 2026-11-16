module QuotesHelper
  # Where a quote opens for staff: the builder for a draft, its own page once it's sent (QTE-06).
  def staff_quote_path(quote) = quote.editable? ? edit_admin_quote_path(quote) : admin_quote_path(quote)

  STATUS_TONES = { "draft" => :neutral, "sent" => :info, "changes_requested" => :warning, "approved" => :success,
                   "declined" => :danger, "expired" => :neutral }.freeze

  # The quote's status for staff: expiry counts, and archived quotes say so.
  def quote_status_badge(quote)
    key = quote.expired? ? "expired" : quote.status
    label = { "sent" => "Sent", "expired" => "Expired", "draft" => "Draft" }.fetch(key) { quote.state_label }
    safe_join([ badge(label, tone: STATUS_TONES.fetch(key)), (badge("Archived", dot: false) if quote.archived?) ].compact, " ")
  end

  # "Not opened" / "Viewed 3×" for a sent quote waiting on the client (QTE-06: an indicator, not a status).
  def quote_viewed_note(quote, views)
    return unless quote.sent? && !quote.expired?

    views.to_i.zero? ? "Not opened" : "Viewed #{views}×"
  end
end
