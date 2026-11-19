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

# BIL-01: the demo business is on Starter (three people; "Powered by Shadetree" off). Run
# `bin/rails plans:comp` or change it in the console to see other plans.
business.update!(plan: Plan.find_by!(key: "starter"), billing_cycle_anchor: 40.days.ago.change(hour: 15)) if business.plan.key == "free" # BIL-02: a billing cycle

{ admin => "admin", technician => "technician" }.each do |user, role|
  BusinessUser.find_or_create_by!(business: business, user: user) { |m| m.role = role }
end

Tenancy.with_business(business) do
  # Hours and closures (CAT-06): weekdays 8–5 and Saturday mornings, Christmas every year,
  # and a half day on the next Christmas Eve.
  business.update!(weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5.merge("6" => { "opens" => "08:00", "closes" => "12:00" })) if business.weekly_hours.nil?
  Closure.find_or_create_by!(reason: "Christmas Day") { _1.assign_attributes(starts_on: Date.new(2026, 12, 25), repeats_yearly: true) }
  eve = Date.new(business.today.year, 12, 24)
  Closure.find_or_create_by!(reason: "Christmas Eve, closing at noon") { _1.assign_attributes(starts_on: eve, part_of_day: true, start_time: "12:00", end_time: "") }
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
                          assignee_ids: [ tech&.id ].compact, instructions: "Start with the front hedges.", created_by: owner,
                          client_note: "Please leave the side gate unlocked.").schedule!(by: owner, notify_client: false) # JOB-05
    from_quote.visits.new(scheduled_on: monday + 1, timing: "exact", start_time: "13:00", duration_minutes: 120,
                          assignee_ids: [ tech&.id, owner.id ].compact, created_by: owner).schedule!(by: owner, notify_client: false)
    from_quote.visits.first.notes.create!(user: tech, body: "Side gate was locked; the client let us in at 9.") if tech # JOB-04
  end

  # JOB-03: a full week on the calendar: weekly mowing for a few clients, spread over the crew,
  # with an overlap, an "anytime" visit and one nobody's on yet.
  unless Job.exists?(title: "Weekly mowing")
    crew = User.where(email: %w[owner@example.com admin@example.com tech@example.com]).index_by(&:email)
    week = business.today.beginning_of_week
    plan = [ [ 0, "exact", "08:00", 90, %w[tech@example.com] ], [ 0, "exact", "10:30", 60, %w[tech@example.com] ],
             [ 1, "window", "09:00", 120, %w[admin@example.com] ], [ 1, "exact", "09:30", 60, %w[tech@example.com] ],
             [ 2, "anytime", nil, 60, %w[owner@example.com] ], [ 2, "exact", "13:00", 120, %w[tech@example.com admin@example.com] ],
             [ 3, "exact", "08:30", 60, [] ], [ 4, "window", "12:00", 90, %w[admin@example.com] ], [ 4, "exact", "15:00", 60, %w[tech@example.com] ] ]
    clients = Client.order(:id).to_a
    plan.each_with_index do |(day, timing, at, minutes, people), index|
      client = clients[index % clients.size] # fewer clients than visits: some get two
      job = Job.create!(client:, property: client.primary_property, created_by: owner, title: "Weekly mowing")
      job.visits.new(scheduled_on: week + day, timing:, start_time: at, window_end_time: (timing == "window" ? (Time.zone.parse(at) + 2.hours).strftime("%H:%M") : nil),
                     duration_minutes: minutes, assignee_ids: people.filter_map { crew[_1]&.id }, created_by: owner).schedule!(by: owner, notify_client: false)
    end
  end
end

# PAY-01/PAY-02: the approved quote billed and sent by link (half paid, PAY-05), and a draft
# for the gutter job.
Tenancy.with_business(business) do
  owner = User.find_by!(email: "owner@example.com")
  approved = Quote.find_by(status: "approved")
  if approved && approved.invoices.none?
    invoice = Invoice.from_quote!(approved, by: owner)
    invoice.mark_sent!(by: owner, channel: "link")
    invoice.client_link!
  end
  # PAY-05: part of it paid by check.
  if invoice && invoice.payments.none?
    invoice.record_payment!(by: owner, amount: Money.new(invoice.total_cents / 2, invoice.currency), received_on: business.today, payment_method: "check",
                            reference: "1042", note: "Half now, the rest when the job's done.")
  end
  gutters = Job.find_by(title: "Gutter cleaning")
  Invoice.from_job!(gutters, by: owner) if gutters && Invoice.where(job: gutters).none?
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
  # NTF-03: one customized client email (Settings → Messages; editing needs a plan with templates).
  MessageTemplate.create_with(subject: "See you tomorrow, {{client_first_name}}",
                              body: "Hi {{client_first_name}},\n\nJust a reminder that we'll be there tomorrow, {{visit_window}}. " \
                                    "Please leave the side gate unlocked.\n\nThanks!").find_or_create_by!(kind: "visit_reminder")
  # NTF-04: the quote follow-up recipe (Settings → Automations; runs need a plan with automations).
  AutomationRecipe.install!("quote_follow_up", by: owner) unless AutomationRule.exists?(recipe: "quote_follow_up")
  puts "Request form: http://localhost:3000/request/#{business.handle}"
end

# MKT-02: a couple of contact-form messages, one flagged as spam.
unless ContactMessage.exists?
  ContactMessage.create!(name: "Dana Whitfield", email: "dana@example.com", business_name: "Whitfield Cleaning", industry: "cleaning",
                         body: "We're a crew of four. Can each cleaner see only their own visits?", notified_at: Time.current)
  ContactMessage.create!(name: "SEO Pro", email: "seo@example.com", body: "Cheap backlinks for your site", spam_reason: "spam words")
end

puts "Demo data ready. Sign in as owner@example.com, admin@example.com or tech@example.com " \
     "with password #{demo_password}."

# ACC-06: a second signed-in browser for the demo owner, so the account page's list has two.
owner = User.find_by!(email: "owner@example.com")
unless owner.user_sessions.active.where("user_agent LIKE ?", "%iPhone%").exists?
  owner.user_sessions.create!(secret_digest: UserSession.digest(SecureRandom.base58(32)), last_active_at: 3.hours.ago, ip_address: "203.0.113.24",
                              user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
end

# ACC-06: a former member who deleted their account, so the team page and past work show it.
unless User.where.not(deleted_at: nil).exists?
  former = User.create!(email: "former@example.com", password: demo_password, first_name: "Jordan", last_name: "Lee", confirmed_at: 1.year.ago)
  BusinessUser.create!(user: former, business:, role: "technician")
  former.delete_account!
end
