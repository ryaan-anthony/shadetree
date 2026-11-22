# PLT-14: the staff pages, in one list, for every check that sweeps the app: the axe tests
# (test/system/accessibility_test.rb) and the design-system checks (PLT-14 to PLT-22,
# test/integration/admin/design_system_test.rb). Records come from fixtures and are made here,
# never from the dev seeds, with each detail page in its main states.
#
#   pages = StaffPages.build(businesses(:one), users(:one))
#   pages.each { |page| get page.path }      # page.name says which page and state
#   StaffPages.build(...).select(&:detail?)  # only the detail pages
#   StaffPages.empty                         # the lists with nothing in them (before build)
#
# Add a page here when you add one to the app; a state worth checking gets its own entry.
module StaffPages
  Page = Data.define(:name, :path, :kind) do
    def detail? = kind == :detail
    def to_s = "#{name} (#{path})"
  end

  extend self

  def build(business, user)
    Builder.new(business, user).pages
  end

  # The lists in their empty state: visit them before build makes any records.
  def empty
    helpers = Rails.application.routes.url_helpers
    { "Requests: empty" => helpers.admin_service_requests_path, "Clients: empty" => helpers.admin_clients_path,
      "Quotes: empty" => helpers.admin_quotes_path, "Jobs: empty" => helpers.admin_jobs_path,
      "Invoices: empty" => helpers.admin_invoices_path, "Services: empty" => helpers.admin_catalog_items_path,
      "Taxes: empty" => helpers.admin_tax_rates_path }.map { |name, path| Page.new(name:, path:, kind: :empty) }
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
      Tenancy.with_business(business) { records }
      lists + forms + details + settings
      @pages
    end

    private

    def page(name, path, kind = :page) = @pages << Page.new(name:, path:, kind:)

    def lists
      page "Home", admin_root_path
      page "My day", admin_my_day_path
      page "Requests", admin_service_requests_path
      page "Requests: in progress", admin_service_requests_path(status: "in_progress")
      page "Clients", admin_clients_path
      page "Quotes", admin_quotes_path
      page "Jobs", admin_jobs_path
      page "Invoices", admin_invoices_path
      page "Schedule", admin_schedule_path
      page "Services", admin_catalog_items_path
      page "Notifications", admin_notifications_path
      page "Help", admin_support_tickets_path
    end

    def forms
      page "Log a request", new_admin_service_request_path
      page "New client", new_admin_client_path
      page "Edit client", edit_admin_client_path(@client)
      page "New quote", new_admin_quote_path
      page "Quote builder (draft)", edit_admin_quote_path(@draft)
      page "Send quote", new_admin_quote_send_path(@sent)
      page "New job", new_admin_job_path
      page "Edit job", edit_admin_job_path(@job)
      page "Schedule a visit", new_admin_job_visit_path(@job)
      page "New invoice", new_admin_invoice_path
      page "Invoice builder (draft)", edit_admin_invoice_path(@draft_invoice)
      page "Send invoice", new_admin_invoice_send_path(@sent_invoice)
      page "Record a payment", new_admin_invoice_payment_path(@sent_invoice)
      page "New service", new_admin_catalog_item_path
      page "Edit service", edit_admin_catalog_item_path(@service)
      page "New tax rate", new_admin_tax_rate_path
      page "Edit tax rate", edit_admin_tax_rate_path(@tax_rate)
      page "New closure", new_admin_closure_path
      page "Assign a follow-up", edit_admin_service_request_follow_up_path(@followed_up)
      page "Schedule: new visit", admin_schedule_new_visit_path
      page "Erase a client's details", new_admin_client_erasure_path(@client)
      page "New support ticket", new_admin_support_ticket_path
    end

    def details
      page "Client", admin_client_path(@client), :detail
      page "Client: archived", admin_client_path(@archived_client), :detail
      page "Request: new", admin_service_request_path(@request), :detail
      page "Request: with a follow-up", admin_service_request_path(@followed_up), :detail
      page "My day: request", admin_my_request_path(@followed_up), :detail
      page "Quote: sent", admin_quote_path(@sent), :detail
      page "Quote: changes requested", admin_quote_path(@changes), :detail
      page "Quote: approved, no job", admin_quote_path(@approved), :detail
      page "Quote: job, no invoice", admin_quote_path(@with_job), :detail
      page "Quote: job and invoice", admin_quote_path(@billed), :detail
      page "Job: open, with a visit", admin_job_path(@job), :detail
      page "Job: completed", admin_job_path(@completed_job), :detail
      page "Job: cancelled", admin_job_path(@cancelled_job), :detail
      page "Visit on My day", admin_my_visit_path(@visit), :detail
      page "Visit on the schedule", admin_schedule_visit_path(@visit), :detail
      page "Invoice: sent", admin_invoice_path(@sent_invoice), :detail
      page "Invoice: paid", admin_invoice_path(@paid_invoice), :detail
    end

    def settings
      page "Settings: business", edit_admin_business_path
      page "Settings: documents", edit_admin_business_path(tab: "documents")
      page "Settings: request form", edit_admin_business_path(tab: "request_form")
      page "Settings: branding", edit_admin_business_path(tab: "branding")
      page "Hours", admin_hours_path
      page "Taxes", admin_tax_rates_path
      # Locations needs a plan with more than one location; the free plan's link goes to Plan.
      page "Team", admin_team_path
      page "Roles", admin_roles_path
      page "Messages", admin_message_templates_path
      page "Automations", admin_automations_path
      page "Notification settings", settings_admin_notifications_path
      page "Payments", admin_payment_account_path
      page "Plan", admin_plan_path
      page "Your data", admin_data_exports_path
      page "Starter services", admin_catalog_presets_path
    end

    def records
      @client = client("Maria Lopez")
      @archived_client = client("Sam Okafor").tap(&:archive!)
      @service = CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
      @tax_rate = TaxRate.create!(name: "State", percent: "6.25")

      @request = ServiceRequest.create!(client: @client, source: "phone", created_by: user, description: "Fence repair")
      @followed_up = ServiceRequest.create!(client: @client, source: "phone", created_by: user, description: "Patio drainage")
      RequestFollowUp.assign!(@followed_up, { user:, scheduled_on: business.today }, by: user)

      @draft = quote("Draft hedges", send: false)
      @sent = quote("Spring cleanup")
      @changes = quote("Fall cleanup").tap { respond(_1, :request_changes, message: "Leave out the side yard.") }
      @approved = quote("Hedge trimming") # approved with the automatic job off (JOB-01), so it has none
      business.update!(auto_create_jobs: false)
      respond(@approved, :approve)
      business.update!(auto_create_jobs: true)
      @with_job = quote("Tree removal").tap { respond(_1, :approve) }
      @billed = quote("Mulching").tap { respond(_1, :approve) }
      Invoice.from_job!(@billed.reload.job, by: user)

      @job = job("Gutter cleaning")
      @visit = @job.visits.new(scheduled_on: business.today, timing: "exact", start_time: "09:00", duration_minutes: 60,
                               assignee_ids: [ user.id ], created_by: user).tap { _1.schedule!(by: user, notify_client: false) }
      @completed_job = job("Spring aeration").tap { _1.complete!(by: user) }
      @cancelled_job = job("Pressure washing").tap { _1.cancel!(by: user, notify_client: false) }

      @draft_invoice = Invoice.from_job!(job("Leaf removal"), by: user)
      @sent_invoice = Invoice.from_job!(job("Window cleaning"), by: user).tap { _1.mark_sent!(by: user, channel: "link") }
      @paid_invoice = Invoice.from_job!(job("Edging"), by: user).tap do |invoice|
        invoice.mark_sent!(by: user, channel: "link")
        invoice.record_payment!(by: user, amount: Money.new(invoice.total_cents, invoice.currency), received_on: business.today, payment_method: "check")
      end
    end

    def client(name)
      Client.create!(display_name: name, contact_methods_attributes: [ { kind: "email", value: "#{name.parameterize}@example.com" } ],
                     properties_attributes: [ { address_line1: "12 Elm St", city: "Asheville", region: "NC", postal_code: "28801" } ])
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
  end
end
