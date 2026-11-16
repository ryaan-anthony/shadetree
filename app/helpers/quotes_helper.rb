module QuotesHelper
  # Where a quote opens for staff: the builder for a draft, the read-only client preview once
  # it's sent (a sent quote's own page comes with QTE-06).
  def staff_quote_path(quote) = quote.editable? ? edit_admin_quote_path(quote) : preview_admin_quote_path(quote)
end
