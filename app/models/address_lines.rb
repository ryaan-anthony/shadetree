# A postal address as it appears on documents, skipping blanks: the business profile's
# (CAT-01) and each location's (CAT-07). The country is named only outside the US.
module AddressLines
  def self.for(record)
    city_line = [ record.city, [ record.region, record.postal_code ].compact_blank.join(" ") ].compact_blank.join(", ")
    [ record.address_line1, record.address_line2, city_line, (Country.find(record.country)&.name if record.country != "US") ].compact_blank
  end
end
