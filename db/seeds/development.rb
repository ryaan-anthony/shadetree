# Demo data for local development. Safe to run repeatedly.
# Sign in as any of these users with the password below.

demo_password = "shadetree-demo-1"

def demo_user(email, first_name, last_name, password)
  User.find_or_initialize_by(email: email).tap do |user|
    user.first_name = first_name
    user.last_name = last_name
    if user.new_record?
      user.password = password
      user.skip_confirmation!
    end
    user.save!
  end
end

owner = demo_user("owner@example.com", "Dana", "Whitaker", demo_password)
admin = demo_user("admin@example.com", "Priya", "Shah", demo_password)
technician = demo_user("tech@example.com", "Marcus", "Reyes", demo_password)

business = Business.find_or_create_by!(name: "Oakline Lawn & Landscape", owner: owner) do |b|
  b.industry = "landscaping"
  b.email = "hello@oakline.example.com"
  b.phone = "(555) 380-4410"
  b.timezone = "America/New_York"
  b.currency = "USD"
  b.brand_color = "#9A3412"
  b.onboarded_at = Time.current
end

{ admin => "admin", technician => "technician" }.each do |user, role|
  BusinessUser.find_or_create_by!(business: business, user: user) { |m| m.role = role }
end

Tenancy.with_business(business) do
  # Tax rates (CAT-04): state and county, applied to new documents.
  TaxRate.find_or_create_by!(name: "State sales tax") { _1.percent = "6.25" }
  TaxRate.find_or_create_by!(name: "County") { _1.percent = "1" }
  # Catalog (CAT-03, CAT-05): the landscaping starter services, with demo prices.
  preset = IndustryPreset.for("landscaping")
  preset&.add_to_catalog!(preset.item_list.map(&:name))
  { "Lawn mowing" => "45", "Leaf cleanup" => "180", "Spring cleanup" => "240", "Mulch installation" => "85",
    "Fertilizer application" => "65", "Aeration" => "120" }.each do |name, price|
    item = CatalogItem.find_by(name:)
    item.update!(unit_price: price) if item && item.unit_price.nil?
  end

  # Clients (CLI-01, CLI-02).
  [
    [ "Maria Lopez", "Lopez Rentals", "(555) 380-1200", "maria@lopez.example.com", "12 Elm St", %w[commercial weekly] ],
    [ "Sam Okafor", nil, "555-380-2299", nil, "9 Oak Ave", %w[weekly] ],
    [ "Grace Chen", nil, "555.380.3141", "grace.chen@example.com", "77 Birch Rd", [] ],
    [ "Riverside HOA", "Riverside Homeowners Assoc.", "555-380-4000", "board@riverside.example.com", "1 Riverside Dr", %w[commercial] ],
    [ "Tom Becker", nil, "555-380-5512", nil, "403 Maple Ct", [] ]
  ].each do |name, company, phone, email, street, tags|
    next if Client.exists?(display_name: name)

    contacts = [ { kind: "phone", value: phone, label: "Mobile" } ]
    contacts << { kind: "email", value: email } if email
    Client.create!(display_name: name, company_name: company, tags:, contact_methods_attributes: contacts,
                   properties_attributes: [ { address_line1: street, city: "Asheville", region: "NC", postal_code: "28801", billing: true } ])
  end
end

Tenancy.with_business(business) do
  # A draft quote (QTE-01) for the first demo client, from catalog items.
  maria = Client.find_by(display_name: "Maria Lopez")
  if maria && !Quote.exists?(client: maria)
    quote = Quote.start(client: maria, created_by: owner)
    rows = CatalogItem.where(name: [ "Spring cleanup", "Mulch installation" ]).map.with_index do |item, i|
      { "key" => "seed-#{i}", "catalog_item" => item.uid, "name" => item.name, "description" => item.description,
        "quantity" => i.zero? ? "1" : "4", "unit" => item.unit_label, "unit_price" => item.unit_price&.to_s || "0", "taxable" => "1" }
    end
    quote.title = "Spring cleanup"
    quote.message = "Thanks for walking the yard with me. Here's what we talked about."
    quote.sync_line_items(rows)
    quote.save!
  end
end

puts "Demo data ready. Sign in as owner@example.com, admin@example.com or tech@example.com " \
     "with password #{demo_password}."
