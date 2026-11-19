# CAT-08: a draft quote or invoice moved to another location can take that location's catalog
# prices and default taxes. Offered, never automatic: lines with prices typed by hand stay as
# they are unless staff accept.
module LocationRepricing
  # [line, the location's price] for catalog lines priced differently there.
  def location_price_changes
    lines = current_line_items.select(&:catalog_item)
    overrides = LocationPrice.cents_at(location, lines.map(&:catalog_item))
    lines.filter_map do |line|
      price = line.catalog_item.price_at(location, overrides:)
      [ line, price ] if price && price.cents != line.unit_price_cents
    end
  end

  def location_taxes_differ? = tax_rate_list.to_set != TaxRate.for_new_document(client:, location:).to_set

  def repricing_offer? = editable? && (location_price_changes.any? || location_taxes_differ?)

  def reprice_for_location!
    raise ArgumentError, "Only a draft can be re-priced." unless editable?

    location_price_changes.each { |line, price| line.unit_price_cents = price.cents }
    self.tax_rate_list = TaxRate.for_new_document(client:, location:)
    save!
  end
end
