# CAT-08: a draft quote or invoice moved to another location can take that location's catalog
# prices and default taxes. Offered, never automatic, and only for what wasn't changed by hand:
# a catalog line still at the price of the location it was priced for, whose item is priced
# differently at one of the two; default taxes the document still has. Staff accept or keep
# their prices; either way the document is then priced for its location.
module LocationRepricing
  extend ActiveSupport::Concern

  included do
    belongs_to :priced_for_location, class_name: "Location", optional: true
    before_validation(on: :create) { self.priced_for_location ||= location }
  end

  # The location the lines were priced for: the document's own until it moves.
  def pricing_location = priced_for_location || location
  def location_moved? = location.present? && pricing_location&.id != location.id

  # [line, the new location's price] for each line that would change.
  def location_price_changes
    return [] unless location_moved?

    lines = current_line_items.select(&:catalog_item)
    items = lines.map(&:catalog_item)
    before, after = LocationPrice.cents_at(pricing_location, items), LocationPrice.cents_at(location, items)
    lines.filter_map do |line|
      item = line.catalog_item
      next unless before.key?(item.id) || after.key?(item.id)

      was, now = item.price_at(pricing_location, overrides: before), item.price_at(location, overrides: after)
      [ line, now ] if was && now && line.unit_price_cents == was.cents && now.cents != was.cents
    end
  end

  # The new location's default taxes, if they differ and the document still has the old ones.
  def location_tax_change
    return unless location_moved?

    was, now = TaxRate.for_new_document(client:, location: pricing_location), TaxRate.for_new_document(client:, location:)
    [ was, now ] if was.to_set != now.to_set && tax_rate_list.to_set == was.to_set
  end

  def repricing_offer? = editable? && location_moved? && (location_price_changes.any? || location_tax_change.present?)

  # Applies the offer; returns what changed (:prices, :taxes).
  def reprice_for_location!
    raise ArgumentError, "Only a draft can be re-priced." unless editable?

    prices, taxes = location_price_changes, location_tax_change
    prices.each { |line, price| line.unit_price_cents = price.cents }
    self.tax_rate_list = taxes.last if taxes
    self.priced_for_location = location
    save!
    [ (:prices if prices.any?), (:taxes if taxes) ].compact
  end

  def keep_prices_for_location! = update!(priced_for_location: location)
end
