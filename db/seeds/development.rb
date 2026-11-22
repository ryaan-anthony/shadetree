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
  # CAT-07: a second location (the locations feature is comped for the demo), where Priya works.
  business.update!(plan_overrides: business.plan_overrides.deep_merge("features" => { "locations" => true }))
  north = Location.find_or_create_by!(name: "North yard") do |location|
    location.assign_attributes(phone: "(555) 380-4499", email: "north@example.com", address_line1: "88 Ridge Road", city: "Brookfield", region: "CT", postal_code: "06804")
  end
  LocationMember.find_or_create_by!(location: north, user: admin)
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
  # CAT-08: North yard charges more for mowing and applies only the state tax by default.
  mowing = CatalogItem.find_by(name: "Lawn mowing")
  LocationPrice.find_or_create_by!(location: north, catalog_item: mowing) { _1.unit_price = "55" } if mowing
  north.update!(tax_rate_ids: TaxRate.where(name: "State sales tax").pluck(:id)) if north.tax_rate_ids.nil?

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
  # QA #274: that quote then emailed, and the mail server refused it (recorded as the delivery
  # job would; nothing is sent), so it shows the "Email not delivered" warning and Resend.
  undelivered = sent_to && Quote.find_by(client: sent_to, status: "sent")
  if undelivered && undelivered.sends.none? { _1.channel == "email" }
    email = EmailMessage.create!(kind: "quote_sent", to: sent_to.primary_email&.value || "client@example.com", related: undelivered)
    undelivered.mark_sent!(by: owner, channel: "email", recipient: email.to, email_message: email)
    email.mark!("failed", error: "The mail server refused the email (554 5.7.1).", announce: true)
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
    logged = ServiceRequest.create!(client:, property: client&.properties&.first, source: "phone", created_by: owner, status: "in_progress", location: Location.find_by(name: "North yard"),
                                    description: "Called about monthly grounds maintenance next season. Wants a quote by Dec 15.")
    logged.notes.create!(business:, user: owner, body: "Site visit booked for Thursday.")
  end
  # CLI-07: follow-ups. The phoned-in request is a site visit for Priya on Thursday afternoon;
  # the form's request is a call for the owner that was due yesterday (overdue in the inbox).
  unless RequestFollowUp.exists?
    priya = User.find_by(email: "admin@example.com")
    thursday = business.today + ((4 - business.today.wday) % 7)
    phoned = ServiceRequest.find_by(source: "phone")
    if phoned && priya
      RequestFollowUp.assign!(phoned, { user: priya, scheduled_on: thursday, timing: "window", start_time: "13:00", window_end_time: "15:00",
                                        instructions: "Walk the grounds with the facilities manager. Note the beds and the slope." }, by: owner)
    end
    online = ServiceRequest.find_by(source: "form")
    RequestFollowUp.assign!(online, { user: owner, kind: "call", scheduled_on: business.today - 1, instructions: "Ask how big the back yard is." }, by: owner) if online&.open?
  end
  # NTF-03: one customized client email (Settings → Messages; editing needs a plan with templates).
  MessageTemplate.create_with(subject: "See you tomorrow, {{client_first_name}}",
                              body: "Hi {{client_first_name}},\n\nJust a reminder that we'll be there tomorrow, {{visit_window}}. " \
                                    "Please leave the side gate unlocked.\n\nThanks!").find_or_create_by!(kind: "visit_reminder")
  # NTF-04: the quote follow-up recipe (Settings → Automations; runs need a plan with automations).
  AutomationRecipe.install!("quote_follow_up", by: owner) unless AutomationRule.exists?(recipe: "quote_follow_up")
  # ACC-07: a role of the business's own (Team → Roles; giving it needs a plan with custom roles).
  Role.create_with(permissions: %w[schedule field_work]).find_or_create_by!(name: "Dispatcher")
  puts "Request form: http://localhost:3000/request/#{business.handle}"
end

# MKT-02: a couple of contact-form messages, one flagged as spam (operators see them at /ops/messages).
unless ContactMessage.exists?
  ContactMessage.create!(name: "Dana Whitfield", email: "dana@example.com", business_name: "Whitfield Cleaning", industry: "cleaning",
                         body: "We're a crew of four. Can each cleaner see only their own visits?", notified_at: Time.current)
  ContactMessage.create!(name: "SEO Pro", email: "seo@example.com", body: "Cheap backlinks for your site", spam_reason: "spam words")
end
# MKT-02 part 2: one already answered, for the console's Handled tab.
unless ContactMessage.handled.exists?
  ContactMessage.create!(name: "Luis Ortega", email: "luis@example.com", business_name: "Ortega Pool Care", industry: "other",
                         body: "Do you support recurring weekly visits?", notified_at: 3.days.ago, created_at: 3.days.ago, handled_at: 2.days.ago)
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

# CLI-06: a finished client import with a couple of rows that didn't go in, to see the summary.
Tenancy.with_business(business) do
  unless ClientImport.exists?
    ClientImport.create!(created_by: owner, filename: "old-crm-export.csv", status: "finished", headers: [ "Name", "Email", "Phone" ],
                         mapping: { "0" => "display_name", "1" => "email", "2" => "phone" }, total_rows: 42, processed_rows: 42,
                         created_count: 39, skipped_count: 2, failed_count: 1, started_at: 1.hour.ago, finished_at: 58.minutes.ago,
                         problems: [ { "row" => 7, "reason" => "Skipped: matches Maria Lopez, a client you already have", "values" => [ "Maria L", "maria@example.com", "" ] },
                                     { "row" => 19, "reason" => "Skipped: matches Ben Carter, a client you already have", "values" => [ "Ben Carter", "", "(828) 555-0142" ] },
                                     { "row" => 31, "reason" => "“jo@@example” isn't an email address", "values" => [ "Jo Park", "jo@@example", "" ] } ])
  end
end

# OPS-01: the demo owner is an operator too (open /ops and set up two-factor).
Operator.grant!(owner) unless Operator.for(owner)

# OPS-02: an internal note on the demo business, seen in the console's business page.
business.operator_notes.create!(author: owner, body: "Beta customer since spring. Asked about a second location.", created_at: 2.weeks.ago, updated_at: 2.weeks.ago) unless business.operator_notes.exists?

# OPS-03: a past read-only support visit, listed for Owners on the Team page.
unless AuditEntry.exists?(action: "impersonation.started", business:)
  admin_member = business.business_users.joins(:user).find_by(users: { email: "admin@example.com" })&.user
  if admin_member
    { "impersonation.started" => { mode: "read_only" }, "impersonation.ended" => { minutes: 6, ended: "stopped" } }.each_with_index do |(action, data), index|
      AuditEntry.create!(operator_user: owner, operator_email: owner.email, action:, business:, target_user: admin_member,
                         reason: ("Ticket: PDF logo looks blurry" if index.zero?), data: data.merge(session: "seeded0visit"), created_at: (3.days.ago + (index * 6).minutes))
    end
  end
end

# OPS-05: a support ticket with a reply, an operator's internal note and the owner's answer by email.
Tenancy.with_business(business) do
  unless SupportTicket.exists?
    ticket = SupportTicket.open!(opened_by: owner, subject: "How do I take tax off one invoice?", category: "billing", page: "/admin/invoices",
                                 browser: "Mozilla/5.0 (Macintosh) Safari/605.1.15", body: "Westgate is tax exempt for this building only. How do I take tax off just this invoice?")
    ticket.note!(owner, "Exempt building; check they have the certificate on file.")
    ticket.reply_from_operator!(owner, "Open the invoice, choose Tax on the line, then pick None. Only that invoice changes.")
    ticket.reply_from_member!(owner, "Found it, thanks. Can I make that the default for Westgate?", source: "email")
  end
end

# BIL-04: the demo business's Starter plan as a mirrored Stripe subscription, with its billing
# history (Settings → Plan, and the operator's business page). The ids are made up: they aren't
# in any Stripe account, so with test keys try Checkout from a new business instead.
Tenancy.with_business(business) do
  unless Subscription.exists?
    anchor = business.billing_cycle_anchor || 40.days.ago.change(hour: 15)
    business.update_columns(stripe_customer_id: "cus_demo_oakline") if business.stripe_customer_id.nil?
    starts = anchor.advance(months: ((Time.current.year * 12 + Time.current.month) - (anchor.year * 12 + anchor.month)))
    starts = starts.advance(months: -1) if starts > Time.current
    Subscription.create!(stripe_subscription_id: "sub_demo_oakline", status: "active", plan: Plan.find_by!(key: "starter"), interval: "monthly",
                         current_period_start: starts, current_period_end: starts.advance(months: 1), billing_cycle_anchor: anchor)
    BillingEvent.record!("subscribed", details: { "plan" => "Starter", "interval" => "monthly" }, at: anchor)
    BillingEvent.record!("plan_changed", details: { "from" => "Free", "to" => "Starter" }, at: anchor)
    [ anchor, anchor.advance(months: 1) ].select { _1 <= Time.current }.each_with_index do |paid_at, index|
      BillingEvent.record!("payment_succeeded", details: { "amount_cents" => 1900, "currency" => "usd", "invoice" => "DEMO-000#{index + 1}" },
                                                dedupe_key: "paid:demo#{index}", at: paid_at + 1.minute)
    end
  end
end
business.with_lock { Billing::PlanResolver.apply!(business) } # BIL-05: billing status from the above
# PAY-03: a connected Stripe account (a made-up id; nothing calls Stripe until it's used), active,
# so Settings → Payments shows its status and client invoices can offer Pay (PAY-04).
Tenancy.with_business(business) do
  unless PaymentAccount.exists?
    PaymentAccount.create!(account_id: "acct_1DemoOaklineLawn", country: "US", details_submitted: true, charges_enabled: true,
                           payouts_enabled: true, synced_at: Time.current, connected_by: owner)
  end
end

# PAY-04: part payments allowed, and $50 of the approved quote's invoice paid online by card
# (recorded as Stripe's notification would; nothing calls Stripe).
business.update!(online_partial_payments: true)
Tenancy.with_business(business) do
  invoice = Invoice.where(status: "partially_paid").order(:id).first
  if invoice && !Payment.exists?(provider_payment_id: "pi_demoOakline0001") && invoice.balance.cents > 5_000
    invoice.record_online_payment!(intent_id: "pi_demoOakline0001", amount_cents: 5_000, currency: invoice.currency, checkout_id: "cs_demoOakline0001",
                                   method_detail: "Visa ending 4242 (Apple Pay)")
  end
end
