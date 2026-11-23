# QTE-08: whether a technician's draft can go to the client without the office's review. It can
# when every line is a service marked "Technicians can send without review", as the catalog has
# it now (its unit, its price at the quote's location and its taxable setting; no line
# discount), with no quote discount, a total (tax included) within the business's cap if it has
# one, the quote at its request's location and priced for it, and the default taxes. Name,
# description and quantity may change; so may terms, valid-until, attachments and the email.
#
#   check = SendWithoutReview.new(quote)
#   check.qualifies?  # => false
#   check.reasons     # => ["Gutter clean: price changed", "Over $500.00"], in the order they're checked
#   check.grounds     # => what's recorded in the quote's history when it's sent
#
# Who it applies to (members who quote their requests but don't send their own) is the
# controllers' call (applies_to?); checked when the builder shows and again inside the send's
# transaction, after the quote row is locked.
class SendWithoutReview
  def self.applies_to?(quote, membership)
    return false unless membership && quote.draft? && quote.revision == 1 && quote.service_request_id

    !membership.can?(:office) && membership.can?(:quote_requests) && !membership.can?(:send_own_quotes) && quote.created_by_id == membership.user_id
  end

  attr_reader :quote

  def initialize(quote)
    @quote = quote
  end

  def qualifies? = reasons.empty?
  def reason = reasons.first

  def reasons
    @reasons ||= begin
      lines = quote.current_line_items
      # The location first: prices are checked against it, so a moved quote isn't misread as a price list change.
      list = at_request_location? ? [] : [ "Priced for another location" ]
      list += lines.empty? ? [ "Add a service first" ] : lines.filter_map { line_reason(_1) }
      list << "Quote discount" if quote.discounted?
      list << "Tax changed" unless default_taxes?
      list << "Over #{cap.format}" if cap && quote.totals.total > cap
      list
    end
  end

  # For the quote's history: the services (as named on the quote, with the catalog's name when it
  # was renamed: "Full roof replacement (Gutter clean)"), the total and the cap it was within.
  def grounds
    services = quote.current_line_items.map do |line|
      service = line.catalog_item.name
      line.name.present? && line.name != service ? "#{line.name} (#{service})" : service
    end
    { "services" => services.uniq, "total" => quote.totals.total.format, "cap" => cap&.format }
  end

  private

  def cap = quote.business.without_review_cap

  def line_reason(line)
    item = line.catalog_item
    name = line.name.presence || item&.name || "A line"
    return "#{name}: custom line" unless item
    return "#{name}: service archived" if item.archived?
    return "#{name}: not one you can send without review" unless item.send_without_review
    return "#{name}: unit changed" if line.unit.to_s != item.unit_label
    return "#{name}: discount" if line.discounted?
    # No list price to keep ("Price on quote"), even where a location has its own (owner, 2026-11-22).
    return "#{name}: priced on each quote" if item.unit_price_cents.nil?

    price = item.price_at(quote.location, overrides: location_prices)
    return "#{name}: price changed" if line.taxable != item.taxable # a taxable change counts as a price edit (owner, 2026-11-22)
    return if line.unit_price_cents == price.cents

    # Still at the price it was added at, so the price list moved, not the technician.
    line.catalog_price_cents.present? && line.unit_price_cents == line.catalog_price_cents ? "#{name}: the price list changed" : "#{name}: price changed"
  end

  def location_prices
    @location_prices ||= LocationPrice.cents_at(quote.location, quote.current_line_items.filter_map(&:catalog_item))
  end

  # CAT-08: its prices are its location's, and that's the request's location.
  def at_request_location?
    quote.location_id == quote.service_request&.location_id && quote.pricing_location&.id == quote.location_id
  end

  def default_taxes?
    !quote.prices_include_tax && quote.tax_rate_list.to_set == TaxRate.for_new_document(client: quote.client, location: quote.location).to_set
  end
end
