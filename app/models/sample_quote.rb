# ACC-05: a realistic quote to preview on the client page before entering real data. Built in
# memory and never saved: no client, number, link or usage event is created. It uses the
# business's branding and terms, its own catalog prices when it has some, else its industry's
# starter services, else a generic job.
class SampleQuote
  def self.build(business) = new(business).build

  def initialize(business)
    @business = business
  end

  def build
    rows = lines
    quote = Quote.new(business:, number: "#{business.quote_number_prefix.presence || "Q"}-SAMPLE", status: "sent", currency: business.currency_code,
                      title: rows.first["name"], terms: business.quote_terms, sent_at: Time.current,
                      expires_on: business.today + business.quote_expiry_days.to_i.clamp(1, 365),
                      message: "Thanks for having us out. Here's what we talked about; any questions, just reply.")
    quote.client = Client.new(business:, display_name: "Jordan Rivera")
    quote.property = Property.new(business:, client: quote.client, address_line1: "12 Maple Street", city: business.city.presence || "Springfield",
                                  region: business.region, postal_code: business.postal_code, country: business.country)
    quote.tax_rate_list = TaxRate.for_new_document
    quote.sync_line_items(rows)
    quote
  end

  private

  attr_reader :business

  def lines
    priced = CatalogItem.active.ordered.where.not(unit_price_cents: [ nil, 0 ]).limit(3).to_a
    return priced.each_with_index.map { |item, i| row(i, item.name, item.description, i.zero? ? 1 : 2, item.unit_label, item.unit_price.to_s) } if priced.any?

    preset = IndustryPreset.for(business.industry)
    starter = preset&.item_list&.first(3)
    # Starter services have no prices yet: plausible placeholders.
    return starter.each_with_index.map { |item, i| row(i, item.name, item.description, 1, nil, %w[180 95 60][i]) } if starter.present?

    [ row(0, "Site visit and assessment", "Walk the property and agree the scope", 1, nil, "75"),
      row(1, "Labor", "Two-person crew", 4, "hour", "65"),
      row(2, "Materials", "Supplied and installed", 1, nil, "180") ]
  end

  def row(index, name, description, quantity, unit, price)
    { "key" => "sample-#{index}", "name" => name, "description" => description, "quantity" => quantity.to_s, "unit" => unit,
      "unit_price" => price.to_s, "taxable" => "1" }
  end
end
