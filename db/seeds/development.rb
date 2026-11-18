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

  # A sent quote (QTE-04: sent as a link, so the seed sends no email), to see the client page.
  sent_to = Client.where.not(id: maria&.id).order(:id).first
  if sent_to && !Quote.exists?(client: sent_to)
    quote = Quote.start(client: sent_to, created_by: owner)
    item = CatalogItem.find_by(name: "Spring cleanup")
    quote.title = "Weekly mowing, spring"
    quote.sync_line_items([ { "key" => "seed-0", "catalog_item" => item&.uid, "name" => item&.name || "Spring cleanup",
                              "quantity" => "1", "unit_price" => item&.unit_price&.to_s || "150", "taxable" => "1" } ])
    quote.save!
    quote.mark_sent!(by: owner, channel: "link")
    link = quote.client_link!
    puts "Client page for quote #{quote.number}: http://localhost:3000/c/#{link.token}"
  end

  # QTE-05: one quote the client approved through their link, one they asked to change. (The
  # team notices and the approval confirmation go to letter_opener when the queue runs.)
  [ [ "Hedge trimming", :approve, { signer_name: nil, terms_accepted: "1", ip_address: "127.0.0.1", device: "iPhone, Safari" } ],
    [ "Fall cleanup", :request_changes, { message: "Could you leave out the side yard? We'll do that one ourselves." } ] ].each_with_index do |(title, action, attributes), index|
    client = Client.order(:id).offset(2 + index).first
    next if client.nil? || Quote.exists?(client:)

    quote = Quote.start(client:, created_by: owner)
    quote.title = title
    quote.sync_line_items([ { "key" => "seed-0", "name" => title, "quantity" => "1", "unit_price" => "240", "taxable" => "1" } ])
    quote.save!
    quote.mark_sent!(by: owner, channel: "link")
    link = quote.client_link!
    attributes = attributes.merge(signer_name: client.display_name) if action == :approve
    quote.record_response!(action, link:, version: quote.lock_version, **attributes)
  end

  # QTE-06: the changes request answered with a revision, sent again.
  changed = Quote.find_by(title: "Fall cleanup", status: "changes_requested", revision: 1)
  if changed
    changed.revise!(by: owner)
    changed.sync_line_items([ { "key" => "seed-0", "name" => "Fall cleanup", "description" => "Front and back; side yard left out",
                                "quantity" => "1", "unit_price" => "200", "taxable" => "1" } ])
    changed.save!
    changed.mark_sent!(by: owner, channel: "link")
  end

  # JOB-01: the approved quote above became a job on its own; add one agreed by phone, with
  # crew instructions, and one already done.
  first_client = Client.order(:id).first
  if first_client && !Job.exists?(quote_id: nil)
    gutters = Job.new(client: first_client, property: first_client.primary_property, created_by: owner, title: "Gutter cleaning",
                      instructions: "Ladder goes on the left side of the house. Bag the debris and leave it by the curb.")
    gutters.line_items.build(name: "Gutter cleaning", description: "Front and back, with downspouts flushed", quantity: 1, unit: "visit", unit_price: "165")
    gutters.save!
    Job.create!(client: first_client, property: first_client.primary_property, created_by: owner, title: "Spring aeration").complete!(by: owner)
  end

  # JOB-02: the job from the approved quote booked over two days with the technician, one in
  # an arrival window and one at a start time.
  from_quote = Job.where.not(quote_id: nil).first
  if from_quote && from_quote.visits.none?
    tech = User.find_by(email: "tech@example.com")
    monday = business.today.next_occurring(:monday)
    from_quote.visits.new(scheduled_on: monday, timing: "window", start_time: "08:00", window_end_time: "10:00", duration_minutes: 180,
                          assignee_ids: [ tech&.id ].compact, instructions: "Start with the front hedges.", created_by: owner).schedule!(by: owner)
    from_quote.visits.new(scheduled_on: monday + 1, timing: "exact", start_time: "13:00", duration_minutes: 120,
                          assignee_ids: [ tech&.id, owner.id ].compact, created_by: owner).schedule!(by: owner)
  end
end

# CLI-03: the request form, on, with a request from someone new.
business.update!(request_form_enabled: true)
Tenancy.with_business(business) do
  unless ServiceRequest.exists?
    services = CatalogItem.active.where(show_on_request_form: true).ordered.limit(2).map(&:uid)
    RequestSubmission.new(business:, name: "Hannah Brooks", email: "hannah@example.com", address_line1: "12 Maple St",
                          city: "Asheville", region: "NC", postal_code: "28801", timing: "In the next few weeks",
                          description: "Front and back yard. The back gets a lot of shade.", service_ids: services).save
  end
  # CLI-04: one logged by phone, already in progress.
  unless ServiceRequest.exists?(source: "phone")
    client = Client.order(:id).offset(1).first
    logged = ServiceRequest.create!(client:, property: client&.properties&.first, source: "phone", created_by: owner, status: "in_progress",
                                    description: "Called about monthly grounds maintenance next season. Wants a quote by Dec 15.")
    logged.notes.create!(business:, user: owner, body: "Site visit booked for Thursday.")
  end
  puts "Request form: http://localhost:3000/request/#{business.handle}"
end

puts "Demo data ready. Sign in as owner@example.com, admin@example.com or tech@example.com " \
     "with password #{demo_password}."
