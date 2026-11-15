# Countries a business can be in at launch, with their default currency and address wording
# (CAT-01). Adding one is a data change here.
module Country
  Entry = Data.define(:code, :name, :currency, :region_label, :postal_label)

  SUPPORTED = [
    Entry.new("US", "United States", "USD", "State", "ZIP code"),
    Entry.new("CA", "Canada", "CAD", "Province", "Postal code"),
    Entry.new("GB", "United Kingdom", "GBP", "County", "Postcode"),
    Entry.new("IE", "Ireland", "EUR", "County", "Eircode"),
    Entry.new("AU", "Australia", "AUD", "State", "Postcode"),
    Entry.new("DE", "Germany", "EUR", "State", "Postal code"),
    Entry.new("FR", "France", "EUR", "Region", "Postal code"),
    Entry.new("ES", "Spain", "EUR", "Province", "Postal code"),
    Entry.new("IT", "Italy", "EUR", "Province", "Postal code"),
    Entry.new("NL", "Netherlands", "EUR", "Province", "Postal code")
  ].freeze

  def self.codes = SUPPORTED.map(&:code)
  def self.find(code) = SUPPORTED.find { _1.code == code.to_s.upcase }
  def self.options = SUPPORTED.map { [ _1.name, _1.code ] }
  def self.currency_for(code) = find(code)&.currency
end
