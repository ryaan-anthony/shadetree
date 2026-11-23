# PLT-14: the staff pages, in one list, for every check that sweeps the app: the axe tests
# (test/system/accessibility_test.rb) and the design-system checks (PLT-14 to PLT-22,
# test/integration/admin/design_system_test.rb). Records come from fixtures and are made here,
# never from the dev seeds, with each detail page in its main states.
#
#   pages = StaffPages.build(businesses(:one), users(:one))  # makes the records
#   pages.each { |page| get page.path }                       # page.key, page.name, page.kind
#   StaffPages.find(pages, :quote_approved)                   # one page by its key
#   StaffPages.empty                                          # the lists with nothing in them (before build)
#
# kind: :list, :form, :detail, :settings, :empty, or :ops (the operator console: sign in with
# sign_in_operator). head: false for a page with no page header (.page-head): only the
# schedule's visit panel, by design (PLT-15 gave the rest page_header).
# Add a page here when you add one to the app; a state worth checking gets its own entry.
module StaffPages
  Page = Data.define(:key, :name, :path, :kind, :head) do
    def initialize(key:, name:, path:, kind:, head: true) = super
    def detail? = kind == :detail
    def ops? = kind == :ops
    def to_s = "#{name} (#{path})"
  end

  extend self

  def build(business, user)
    Builder.new(business, user).pages
  end

  def find(pages, key) = pages.find { _1.key == key } || raise(KeyError, "No staff page #{key.inspect}")

  # The lists in their empty state: visit them before build makes any records.
  def empty
    helpers = Rails.application.routes.url_helpers
    { requests: [ "Requests", helpers.admin_service_requests_path ], clients: [ "Clients", helpers.admin_clients_path ],
      quotes: [ "Quotes", helpers.admin_quotes_path ], jobs: [ "Jobs", helpers.admin_jobs_path ],
      invoices: [ "Invoices", helpers.admin_invoices_path ], services: [ "Services", helpers.admin_catalog_items_path ],
      taxes: [ "Taxes", helpers.admin_tax_rates_path ] }.map do |key, (name, path)|
      Page.new(key: :"#{key}_empty", name: "#{name}: empty", path:, kind: :empty)
    end
  end

  class Builder
    include Rails.application.routes.url_helpers

    attr_reader :business, :user

    def initialize(business, user)
      @business = business
      @user = user
      @pages = []
    end

    def pages
      # Plan features, so their pages show rather than send you to Plan.
      business.update!(plan_overrides: { "features" => %w[automations message_templates locations custom_roles].index_with(true) })
      Tenancy.with_business(business) { records }
      lists + forms + details + settings + ops
      @pages
    end

    private

    def page(key, name, path, kind, head: true) = @pages << Page.new(key:, name:, path:, kind:, head:)

    def lists
      page :home, "Home", admin_root_path, :list
      page :my_day, "My day", admin_my_day_path, :list
      page :requests, "Requests", admin_service_requests_path, :list
      page :requests_in_progress, "Requests: in progress", admin_service_requests_path(status: "in_progress"), :list
      page :clients, "Clients", admin_clients_path, :list
      page :quotes, "Quotes", admin_quotes_path, :list
      page :jobs, "Jobs", admin_jobs_path, :list
      page :invoices, "Invoices", admin_invoices_path, :list
      page :schedule, "Schedule", admin_schedule_path, :list
      page :services, "Services", admin_catalog_items_path, :list
      page :notifications, "Notifications", admin_notifications_path, :list
      page :help, "Help", admin_support_tickets_path, :list
    end

    def forms
      page :new_request, "Log a request", new_admin_service_request_path, :form
      page :new_client, "New client", new_admin_client_path, :form
      page :edit_client, "Edit client", edit_admin_client_path(@client), :form
      page :new_client_import, "Import clients", new_admin_client_import_path, :form
      page :edit_client_import, "Import clients: columns", edit_admin_client_import_path(@import), :form
      page :new_quote, "New quote", new_admin_quote_path, :form
      page :quote_builder, "Quote builder (draft)", edit_admin_quote_path(@draft), :form
      page :send_quote, "Send quote", new_admin_quote_send_path(@sent), :form
      page :new_job, "New job", new_admin_job_path, :form
      page :edit_job, "Edit job", edit_admin_job_path(@job), :form
      page :new_visit, "Schedule a visit", new_admin_job_visit_path(@job), :form
      page :edit_visit, "Edit visit", edit_admin_job_visit_path(@job, @visit), :form
      page :new_invoice, "New invoice", new_admin_invoice_path, :form
      page :invoice_builder, "Invoice builder (draft)", edit_admin_invoice_path(@draft_invoice), :form
      page :send_invoice, "Send invoice", new_admin_invoice_send_path(@sent_invoice), :form
      page :new_payment, "Record a payment", new_admin_invoice_payment_path(@sent_invoice), :form
      page :new_service, "New service", new_admin_catalog_item_path, :form
      page :edit_service, "Edit service", edit_admin_catalog_item_path(@service), :form
      page :new_tax_rate, "New tax rate", new_admin_tax_rate_path, :form
      page :edit_tax_rate, "Edit tax rate", edit_admin_tax_rate_path(@tax_rate), :form
      page :new_closure, "New closure", new_admin_closure_path, :form
      page :edit_follow_up, "Assign a follow-up", edit_admin_service_request_follow_up_path(@followed_up), :form
      page :schedule_new_visit, "Schedule: new visit", admin_schedule_new_visit_path, :form
      page :new_erasure, "Erase a client's details", new_admin_client_erasure_path(@client), :form
      page :new_support_ticket, "New support ticket", new_admin_support_ticket_path, :form
      page :new_role, "New role", new_admin_role_path, :form
      page :edit_role, "Edit role", edit_admin_role_path(@role), :form
      page :new_automation, "New automation", new_admin_automation_path, :form
      page :edit_automation, "Edit automation", edit_admin_automation_path(@automation), :form
      page :new_template, "New message template", new_admin_custom_message_template_path, :form
      page :edit_template, "Edit message template", edit_admin_custom_message_template_path(@template), :form
      page :new_location, "New location", new_admin_location_path, :form
      page :edit_location, "Edit location", edit_admin_location_path(@location), :form
      page :edit_closure, "Edit closure", edit_admin_closure_path(@closure), :form
      page :edit_client_note, "Edit a client note", edit_admin_client_note_path(@client, @note), :form
      page :edit_payment, "Edit a payment", edit_admin_invoice_payment_path(@part_paid_invoice, @payment), :form
      page :delete_role, "Delete a role", delete_admin_role_path(@role), :form
    end

    def details
      page :client, "Client", admin_client_path(@client), :detail
      page :client_archived, "Client: archived", admin_client_path(@archived_client), :detail
      page :client_erased, "Client: erased", admin_client_path(@erased_client), :detail
      page :request, "Request: new", admin_service_request_path(@request), :detail
      page :request_followed_up, "Request: with a follow-up", admin_service_request_path(@followed_up), :detail
      page :request_quoted, "Request: quoted", admin_service_request_path(@quoted_request), :detail
      page :request_archived, "Request: archived", admin_service_request_path(@archived_request), :detail
      page :request_archived_client, "Request: archived client", admin_service_request_path(@archived_client_request), :detail
      page :my_request, "My day: request", admin_my_request_path(@followed_up), :detail
      page :quote_sent, "Quote: sent", admin_quote_path(@sent), :detail
      page :quote_changes, "Quote: changes requested", admin_quote_path(@changes), :detail
      page :quote_declined, "Quote: declined", admin_quote_path(@declined), :detail
      page :quote_expired, "Quote: expired", admin_quote_path(@expired), :detail
      page :quote_archived, "Quote: archived", admin_quote_path(@archived_quote), :detail
      page :quote_approved, "Quote: approved, no job", admin_quote_path(@approved), :detail
      page :quote_job_cancelled, "Quote: approved, job cancelled", admin_quote_path(@job_cancelled), :detail
      page :quote_with_job, "Quote: job, no invoice", admin_quote_path(@with_job), :detail
      page :quote_billed, "Quote: job and invoice", admin_quote_path(@billed), :detail
      page :quote_link_after_bounce, "Quote: link copied after a bounce", admin_quote_path(@bounced), :detail
      page :job, "Job: open, with a visit", admin_job_path(@job), :detail
      page :job_unbooked, "Job: open, no visit", admin_job_path(@unbooked_job), :detail
      page :job_completed, "Job: completed", admin_job_path(@completed_job), :detail
      page :job_cancelled, "Job: cancelled", admin_job_path(@cancelled_job), :detail
      page :my_visit, "Visit on My day", admin_my_visit_path(@visit), :detail
      page :schedule_visit, "Visit on the schedule", admin_schedule_visit_path(@visit), :detail, head: false
      page :invoice_sent, "Invoice: sent", admin_invoice_path(@sent_invoice), :detail
      page :invoice_part_paid, "Invoice: part paid", admin_invoice_path(@part_paid_invoice), :detail
      page :invoice_overdue, "Invoice: overdue", admin_invoice_path(@overdue_invoice), :detail
      page :invoice_paid, "Invoice: paid", admin_invoice_path(@paid_invoice), :detail
      page :invoice_void, "Invoice: void", admin_invoice_path(@void_invoice), :detail
      page :invoice_paid_online, "Invoice: paid online", admin_invoice_path(@online_invoice), :detail
      page :support_ticket, "Support ticket", admin_support_ticket_path(@ticket), :detail
      page :client_import, "Client import: finished", admin_client_import_path(@finished_import), :detail
    end

    def settings
      page :settings_business, "Settings: business", edit_admin_business_path, :settings
      page :settings_documents, "Settings: documents", edit_admin_business_path(tab: "documents"), :settings
      page :settings_request_form, "Settings: request form", edit_admin_business_path(tab: "request_form"), :settings
      page :settings_branding, "Settings: branding", edit_admin_business_path(tab: "branding"), :settings
      page :hours, "Hours", admin_hours_path, :settings
      page :taxes, "Taxes", admin_tax_rates_path, :settings
      page :locations, "Locations", admin_locations_path, :settings
      page :team, "Team", admin_team_path, :settings
      page :roles, "Roles", admin_roles_path, :settings
      page :messages, "Messages", admin_message_templates_path, :settings
      page :automations, "Automations", admin_automations_path, :settings
      page :notification_settings, "Notification settings", settings_admin_notifications_path, :settings
      page :payments, "Payments: connected", admin_payment_account_path, :settings
      page :plan, "Plan", admin_plan_path, :settings
      page :data, "Your data", admin_data_exports_path, :settings
      page :starter_services, "Starter services", admin_catalog_presets_path, :settings
    end

    # The operator console (OPS-01 to OPS-05).
    def ops
      page :ops_home, "Ops: home", ops_root_path, :ops
      page :ops_businesses, "Ops: businesses", ops_businesses_path, :ops
      page :ops_business, "Ops: a business", ops_business_path(business), :ops
      page :ops_overrides, "Ops: plan overrides", edit_ops_business_plan_overrides_path(business), :ops
      page :ops_edit_note, "Ops: edit a note", edit_ops_business_note_path(business, @operator_note), :ops
      page :ops_users, "Ops: users", ops_users_path, :ops
      page :ops_operators, "Ops: operators", ops_operators_path, :ops
      page :ops_audit, "Ops: audit log", ops_audit_entries_path, :ops
      page :ops_plans, "Ops: plans", ops_plans_path, :ops
      page :ops_edit_plan, "Ops: edit a plan", edit_ops_plan_path(Plan.find_by!(key: "starter")), :ops
      page :ops_presets, "Ops: presets", ops_presets_path, :ops
      page :ops_flags, "Ops: feature flags", ops_feature_flags_path, :ops
      page :ops_messages, "Ops: contact messages", ops_contact_messages_path, :ops
      page :ops_message, "Ops: a contact message", ops_contact_message_path(@contact_message), :ops
      page :ops_tickets, "Ops: tickets", ops_tickets_path, :ops
      page :ops_ticket, "Ops: a ticket", ops_ticket_path(@ticket), :ops
    end

    def records
      @client = client("Maria Lopez")
      @archived_client = client("Sam Okafor")
      @erased_client = client("Grace Chen")
      @service = CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
      @tax_rate = TaxRate.create!(name: "State", percent: "6.25")
      @location = Location.create!(name: "North yard")
      @closure = Closure.create!(reason: "Thanksgiving", starts_on: business.today + 30)
      @role = Role.create!(name: "Dispatcher", permissions: %w[office])
      @automation = AutomationRule.create!(name: "Tell the office", trigger: "quote_sent", actions: [ { "type" => "notify_team", "team" => "office" } ])
      @template = MessageTemplate.create!(name: "Spring offer", subject: "Spring", body: "Hello")
      @import = ClientImport.create!(created_by: user, filename: "clients.csv", headers: [ "Name", "Phone" ], mapping: { "0" => "display_name", "1" => "phone" })
      @finished_import = ClientImport.create!(created_by: user, filename: "old.csv", headers: [ "Name" ], status: "finished", finished_at: Time.current)
      @ticket = SupportTicket.open!(opened_by: user, subject: "Logo", category: "question", body: "How do I change my logo?")
      PaymentAccount.create!(account_id: "acct_staffpages", details_submitted: true, charges_enabled: true, payouts_enabled: true)

      requests
      quotes
      jobs
      invoices

      @note = ClientNote.create!(client: @client, user:, body: "Prefers morning visits.")
      @archived_client.archive!
      ClientErasure.new(@erased_client, by: user).erase!
      @operator_note = business.operator_notes.create!(author: user, body: "Asked about a second location.")
      @contact_message = ContactMessage.create!(name: "Dana Whitfield", email: "dana@example.com", body: "Do you send reminders?")
    end

    def requests
      @request = request("Fence repair")
      @followed_up = request("Patio drainage")
      RequestFollowUp.assign!(@followed_up, { user:, scheduled_on: business.today }, by: user)
      @quoted_request = request("Gutter guards").tap { _1.update!(status: "quoted") }
      @archived_request = request("Dead maple").tap { _1.update!(status: "archived") }
      @archived_client_request = request("Hedges", client: @archived_client)
    end

    def quotes
      @draft = quote("Draft hedges", send: false)
      @sent = quote("Spring cleanup")
      @changes = quote("Fall cleanup").tap { respond(_1, :request_changes, message: "Leave out the side yard.") }
      @declined = quote("Pond liner").tap { respond(_1, :decline, message: "Too much") }
      @expired = quote("Snow removal").tap { _1.update_columns(expires_on: business.today - 1) }
      @archived_quote = quote("Old patio").tap { respond(_1, :decline, message: "No") }.tap { _1.archive!(by: user) }
      @approved = quote("Hedge trimming") # approved with the automatic job off (JOB-01), so it has none
      @job_cancelled = quote("Stump grinding")
      business.update!(auto_create_jobs: false)
      respond(@approved, :approve)
      business.update!(auto_create_jobs: true)
      respond(@job_cancelled, :approve)
      @job_cancelled.reload.job.cancel!(by: user, notify_client: false)
      @with_job = quote("Tree removal").tap { respond(_1, :approve) }
      @billed = quote("Mulching").tap { respond(_1, :approve) }
      @bounced = quote("Hedge planting", send: false).tap do |quote| # its email bounced, then the link was copied
        email = EmailMessage.create!(kind: "quote_sent", to: "maria-lopez@example.com", related: quote)
        quote.mark_sent!(by: user, channel: "email", recipient: email.to, email_message: email)
        email.mark!("failed", error: "The mail server refused the email (554 5.7.1).")
        quote.mark_sent!(by: user, channel: "link")
      end
      Invoice.from_job!(@billed.reload.job, by: user)
    end

    def jobs
      @job = job("Gutter cleaning")
      @visit = @job.visits.new(scheduled_on: business.today, timing: "exact", start_time: "09:00", duration_minutes: 60,
                               assignee_ids: [ user.id ], created_by: user).tap { _1.schedule!(by: user, notify_client: false) }
      @unbooked_job = job("Shed removal")
      @completed_job = job("Spring aeration").tap { _1.complete!(by: user) }
      @cancelled_job = job("Pressure washing").tap { _1.cancel!(by: user, notify_client: false) }
    end

    def invoices
      @draft_invoice = Invoice.from_job!(job("Leaf removal"), by: user)
      @sent_invoice = sent_invoice("Window cleaning")
      @part_paid_invoice = sent_invoice("Fence painting").tap { pay(_1, _1.total_cents / 2) }
      @payment = @part_paid_invoice.payments.first
      @overdue_invoice = sent_invoice("Drain clearing").tap { _1.update_columns(issued_on: business.today - 40, due_on: business.today - 10) }
      @paid_invoice = sent_invoice("Edging").tap { pay(_1, _1.total_cents) }
      @void_invoice = sent_invoice("Lights").tap { _1.void!(reason: "Billed twice", by: user) }
      @online_invoice = sent_invoice("Hedge edging").tap do |invoice| # PAY-04: paid by card, with Stripe's reference
        invoice.record_online_payment!(intent_id: "pi_staffpages0001", amount_cents: invoice.total_cents, currency: invoice.currency, method_detail: "Visa ending 4242")
      end
    end

    def client(name)
      Client.create!(display_name: name, contact_methods_attributes: [ { kind: "email", value: "#{name.parameterize}@example.com" } ],
                     properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801" } ])
    end

    def request(description, client: @client)
      ServiceRequest.create!(client:, source: "phone", created_by: user, description:)
    end

    def quote(title, send: true)
      Quote.start(client: @client, created_by: user).tap do |quote|
        quote.title = title
        quote.sync_line_items([ { "key" => "a", "name" => title, "quantity" => "1", "unit_price" => "240", "taxable" => "0" } ])
        quote.save!
        quote.mark_sent!(by: user, channel: "link") if send
      end
    end

    def respond(quote, action, **attributes)
      attributes = { signer_name: "Maria Lopez", terms_accepted: "1", ip_address: "127.0.0.1", device: "Computer · Chrome" } if action == :approve
      quote.record_response!(action, link: quote.client_link!, version: quote.lock_version, **attributes)
    end

    def job(title)
      job = Job.new(client: @client, property: @client.primary_property, created_by: user, title:)
      job.line_items.build(name: title, quantity: 1, unit: "visit", unit_price: "120")
      job.tap(&:save!)
    end

    def sent_invoice(title) = Invoice.from_job!(job(title), by: user).tap { _1.mark_sent!(by: user, channel: "link") }

    def pay(invoice, cents)
      invoice.record_payment!(by: user, amount: Money.new(cents, invoice.currency), received_on: business.today, payment_method: "check")
    end
  end
end
