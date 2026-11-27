require "test_helper"

# CAT-07: requests, quotes, jobs and invoices belong to a location, and clients see its details.
class LocationDocumentsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(handle: "oakline", request_form_enabled: true, email: "office@example.com", plan_overrides: { "features" => { "locations" => true } })
    as_business(@business) do
      @north = Location.create!(name: "North yard", phone: "555-0177", email: "north@example.com", address_line1: "88 Ridge Rd", city: "Yonkers")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ],
                              properties_attributes: [ { address_line1: "1 Elm St", billing: true } ])
    end
    @main = @business.primary_location
  end

  def sign_in_owner
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "work moves through a location: request, quote, job and invoice" do
    as_business(@business) do
      request = ServiceRequest.create!(client: @maria, source: "phone", description: "Hedges", location: @north)
      quote = request.create_quote!(by: users(:one))
      assert_equal @north, quote.location
      quote.sync_line_items([ { "key" => "a", "name" => "Hedges", "quantity" => "1", "unit_price" => "100" } ])
      quote.save!
      quote.update_columns(status: "approved")
      job = Job.from_quote!(quote)
      assert_equal @north, job.location
      job.complete!(by: users(:one))
      assert_equal @north, Invoice.from_job!(job).location
      assert_equal @north, quote.duplicate!.location
      assert_equal @main, Quote.start(client: @maria).location, "nobody signed in: the main location"
    end
  end

  test "new documents start at the member's location, and the builder can move them" do
    sign_in_owner
    as_business(@business) { LocationMember.create!(location: @north, user: users(:one)) }
    post admin_quotes_path, params: { quote: { client: @maria.uid } }
    quote = as_business(@business) { Quote.last }
    assert_equal @north.id, quote.location_id
    get edit_admin_quote_path(quote)
    assert_select "select[name='quote[location]'] option[selected]", "North yard"

    theirs = as_business(businesses(:two)) { businesses(:two).primary_location }
    patch admin_quote_path(quote), params: { quote: { lock_version: quote.lock_version, location: theirs.uid } }
    assert_equal @north.id, quote.reload.location_id, "another business's location is ignored"
    patch admin_quote_path(quote), params: { quote: { lock_version: quote.reload.lock_version, location: @main.uid } }
    assert_equal @main.id, quote.reload.location_id

    post admin_jobs_path, params: { job: { client: @maria.uid, property: as_business(@business) { @maria.properties.first.uid }, title: "Mulch", location: @north.uid } }
    assert_equal @north, as_business(@business) { Job.find_by!(title: "Mulch").location }
    get new_admin_service_request_path
    assert_select "select[name='service_request[location]'] option[selected]", "North yard"
  end

  test "another business's location can't be picked when creating a job or request" do
    sign_in_owner
    theirs = businesses(:two).primary_location
    property = as_business(@business) { @maria.properties.first.uid }
    post admin_jobs_path, params: { job: { client: @maria.uid, property:, title: "Sneaky", location: theirs.uid } }
    assert_equal @main.id, as_business(@business) { Job.find_by!(title: "Sneaky").location_id }
    post admin_service_requests_path, params: { service_request: { client: @maria.uid, source: "phone", description: "Sneaky request", location: theirs.uid } }
    assert_equal @main.id, as_business(@business) { ServiceRequest.find_by!(description: "Sneaky request").location_id }
  end

  test "lists, pages and the data export show each document's location" do
    sign_in_owner
    quote = as_business(@business) { Quote.start(client: @maria, location: @north).tap { _1.update!(title: "North quote"); _1.update_columns(status: "sent", sent_at: Time.current) } }
    get admin_quotes_path
    assert_select ".badge", "North yard"
    get admin_quote_path(quote)
    assert_select ".page-lede .badge", "North yard"
    csv, = as_business(@business) { DataExport.table("quotes").generate }
    assert_includes csv.lines.first, "Location"
    assert_includes csv, "North yard"
    assert_includes as_business(@business) { DataExport.table("locations").generate.first }, "North yard"
  end

  test "with one location, documents never show a location" do
    as_business(@business) { @north.destroy! }
    sign_in_owner
    quote = as_business(@business) { Quote.start(client: @maria) }
    get edit_admin_quote_path(quote)
    assert_select "select[name='quote[location]']", 0
    get new_admin_job_path
    assert_select "select[name='job[location]']", 0
    get public_request_path("oakline")
    assert_select "select[name='request_submission[location]']", 0
  end

  test "clients see the location's name and contact details on pages, PDFs and emails" do
    quote = as_business(@business) { Quote.start(client: @maria, location: @north) }
    link = as_business(@business) { ClientLink.issue!(quote) }
    get client_link_path(link.token)
    assert_select "header", /North yard.*555-0177/m
    assert_select "a[href='mailto:north@example.com']"

    html = as_business(@business) { quote.pdf_html }
    assert_includes html, "88 Ridge Rd"
    assert_includes html, "North yard"

    perform_enqueued_jobs { ClientMailer.send_later(:test_message, business: @business, to: "maria@example.com", kind: "test_message", related: quote, recipient_name: "Maria") }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "north@example.com" ], mail.reply_to
    assert_includes mail.text_part.body.to_s, "#{@business.name} · North yard"
    assert_includes mail.html_part.body.to_s, "555-0177"
  end

  test "the request form: a location's own link, or the client chooses" do
    get public_request_path("oakline")
    assert_select "select[name='request_submission[location]'] option", [ "Not sure", @main.name, "North yard" ].size
    get public_request_path("oakline", location: @north.uid)
    assert_select "input[type=hidden][name='request_submission[location]'][value='#{@north.uid}']"
    assert_select "header", /555-0177/

    form_token = Rails.application.message_verifier("form_guard").generate(10.seconds.ago.to_f, purpose: "request:oakline", expires_in: 1.day)
    post public_request_path("oakline"), params: { form_token:, website: "", request_submission: { name: "Hannah", email: "h@example.com", address_line1: "12 Maple St", description: "Lawn", location: @north.uid } }
    assert_equal @north, as_business(@business) { ServiceRequest.last.location }

    post public_request_path("oakline"), params: { form_token:, website: "", request_submission: { name: "Ivy", email: "i@example.com", address_line1: "3 Oak St", description: "Lawn", location: "nope" } }
    assert_response :unprocessable_content

    post public_request_path("oakline"), params: { form_token:, website: "", fixed_location: "1", request_submission: { name: "", email: "j@example.com", address_line1: "4 Oak St", location: @north.uid } }
    assert_response :unprocessable_content
    assert_select "input[type=hidden][name='request_submission[location]'][value='#{@north.uid}']", 1, "a location's own link stays fixed after an error"
    assert_select "select[name='request_submission[location]']", 0
  end
end
