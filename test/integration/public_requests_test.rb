require "test_helper"

# CLI-03: the public request form at /request/<handle>.
class PublicRequestsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(handle: "oakline", request_form_intro: "We reply within a day.", request_form_enabled: true)
    as_business(@business) do
      @mowing = CatalogItem.create!(name: "Weekly mowing", unit: "visit", show_on_request_form: true)
      @hidden = CatalogItem.create!(name: "Internal fee", unit: "each", show_on_request_form: false)
    end
  end

  # A form shown 10 seconds ago (the minimum time on the page is 3).
  def token(at: 10.seconds.ago) = Rails.application.message_verifier("form_guard").generate(at.to_f, purpose: "request:oakline", expires_in: 1.day)

  def submit(handle: "oakline", form_token: token, website: "", **fields)
    fields = { name: "Hannah Brooks", email: "hannah@example.com", phone: "", address_line1: "12 Maple St", postal_code: "06804",
               description: "Front and back lawn, weekly.", timing: "As soon as possible", service_ids: [ @mowing.uid ] }.merge(fields)
    post public_request_path(handle), params: { form_token:, website:, request_submission: fields }
  end

  def requests = as_business(@business) { ServiceRequest.all.to_a }
  def clients = as_business(@business) { Client.all.to_a }

  test "the page is branded and offers the business's form services" do
    get public_request_path("Oakline") # handles are case-insensitive
    assert_response :success
    assert_select "header.client-head", /#{@business.name}/
    assert_select "h1", "Request a quote"
    assert_select "p", "We reply within a day."
    assert_select "label", /Weekly mowing/
    assert_select "label", { text: /Internal fee/, count: 0 }
    assert_select "input[name=website]"
    assert_select "input[name=form_token]"
  end

  test "the business's weekly hours show with its contact details (CAT-06)" do
    @business.update!(request_form_enabled: false, phone: "(555) 380-4410")
    get public_request_path("oakline")
    assert_select "p", { text: /Hours:/, count: 0 }, "nothing until hours are set"
    @business.update!(weekly_hours: WeeklyHours::WEEKDAYS_8_TO_5)
    get public_request_path("oakline")
    assert_select "p", /Hours:\s*Mon–Fri 8 am–5 pm/
  end

  test "a submission from a new person creates a client, property and request, and tells everyone" do
    with_fake_pdf_renderer do
      submit
    end
    assert_redirected_to public_request_sent_path("oakline")
    follow_redirect!
    assert_select "h1", "Request sent"
    assert_select "p", /We've emailed you a confirmation/

    request = requests.sole
    client = as_business(@business) { request.client }
    assert_equal [ "Hannah Brooks", [ "hannah@example.com" ] ], [ client.display_name, as_business(@business) { client.contact_methods.map(&:value) } ]
    assert_equal [ "12 Maple St", true ], as_business(@business) { [ request.property.address_line1, request.property.billing ] }
    assert_equal [ "form", "new", [ "Weekly mowing" ], "As soon as possible", false ],
                 [ request.source, request.status, request.service_names, request.timing, request.matched_existing_client ]

    perform_enqueued_jobs
    team = ActionMailer::Base.deliveries.find { _1.to == [ users(:one).email ] }
    assert_equal "New request from Hannah Brooks", team.subject
    assert_match "Front and back lawn, weekly.", team.text_part.body.to_s
    ack = ActionMailer::Base.deliveries.find { _1.to == [ "hannah@example.com" ] }
    assert_equal "#{@business.name} received your request", ack.subject
    assert_match "Weekly mowing", ack.text_part.body.to_s
    # The acknowledgment repeats nothing the person typed.
    assert_no_match "Front and back lawn", ack.html_part.body.to_s
    assert_no_match "Hannah", ack.html_part.body.to_s
  end

  test "a known email or phone links to that client without changing their record" do
    maria = as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "555-010-0100" } ],
                     properties_attributes: [ { address_line1: "12 Maple Street", postal_code: "06804", billing: true } ])
    end
    submit(email: "someone.else@example.com", phone: "(555) 010-0100", address_line1: "9 Oak Ave")
    request = requests.sole
    assert_equal maria.id, request.client_id
    assert request.matched_existing_client
    as_business(@business) do
      assert_equal [ "555-010-0100" ], maria.reload.contact_methods.map(&:value), "typed contacts aren't added to the client"
      assert_equal [ "12 Maple Street" ], maria.properties.map(&:address_line1), "nor is a new address"
    end
    assert_nil request.property_id
    assert_equal "9 Oak Ave, 06804", request.address_line
    assert_equal [ "someone.else@example.com", "(555) 010-0100" ], [ request.contact_email, request.contact_phone ]

    submit(email: "", phone: "5550100100", address_line1: " 12  maple street ")
    assert_equal as_business(@business) { maria.properties.sole.id }, requests.max_by(&:id).property_id, "a known address links its property"
    assert_equal 1, clients.size
  end

  test "matching never reaches archived clients or another business" do
    as_business(businesses(:two)) { Client.create!(display_name: "Other", contact_methods_attributes: [ { kind: "email", value: "hannah@example.com" } ]) }
    old = as_business(@business) { Client.create!(display_name: "Old", contact_methods_attributes: [ { kind: "email", value: "hannah@example.com" } ]).tap(&:archive!) }
    submit
    assert_not_equal old.id, requests.sole.client_id
    assert_equal "Hannah Brooks", as_business(@business) { requests.sole.client.display_name }
    assert_equal 1, as_business(businesses(:two)) { Client.count }
  end

  test "an email or a phone is enough, and one of them is needed" do
    submit(email: "", phone: "")
    assert_response :unprocessable_content
    assert_select ".error-text", /Add an email or a phone number so we can reply\./
    submit(email: "", phone: "555 010 0199")
    assert_redirected_to public_request_sent_path("oakline")
    assert_equal "phone", as_business(@business) { requests.sole.client.contact_methods.sole.kind }
  end

  test "it needs a name, an address, and a service or a description" do
    submit(name: "", address_line1: "", description: "", service_ids: [], email: "nope")
    assert_response :unprocessable_content
    %w[Tell\ us\ your\ name. Tell\ us\ where\ the\ work\ is. Pick\ a\ service\ or\ tell\ us\ about\ the\ job. That\ email\ doesn't\ look\ right.].each do |message|
      assert_select ".error-text", /#{Regexp.escape(message)}/
    end
    assert_empty requests
  end

  test "photos are kept without their metadata, up to the limit" do
    photo = -> { Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png", original_filename: "yard.png") }
    submit(photos: [ photo.call ])
    assert_equal 1, as_business(@business) { requests.sole.photos.count }

    submit(photos: Array.new(ServiceRequest::MAX_PHOTOS + 1) { photo.call })
    assert_response :unprocessable_content
    assert_select ".error-text", /You can add up to 5 photos\./
  end

  test "the hidden field turns bots away quietly" do
    submit(website: "https://spam.example")
    assert_redirected_to public_request_sent_path("oakline")
    assert_empty requests
    assert_empty clients
    assert_enqueued_jobs 0
  end

  test "a form sent within seconds, left open too long or forged is shown again to send" do
    submit(form_token: token(at: 1.second.ago))
    assert_response :unprocessable_content
    assert_select ".banner-warning", /Check your details, then send it again\./
    assert_select "input[name='request_submission[name]'][value='Hannah Brooks']"
    submit(form_token: "")
    assert_select ".banner-warning", /open for a while/
    other = Rails.application.message_verifier("form_guard").generate(10.seconds.ago.to_f, purpose: "request:two-biz")
    submit(form_token: other)
    assert_response :unprocessable_content
    assert_empty requests

    # Errors come first, however fast: an empty form says what's missing.
    submit(form_token: token(at: 1.second.ago), name: "")
    assert_select ".error-text", /Tell us your name\./
  end

  test "too many attempts from one address are refused, keeping what was typed, and only on that business's page" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    10.times { submit(name: "") }
    submit
    assert_response :unprocessable_content
    assert_select ".banner-warning", /a lot of requests/
    assert_select "input[name='request_submission[name]'][value='Hannah Brooks']"
    assert_empty requests

    businesses(:two).update!(request_form_enabled: true)
    post public_request_path("two-biz"), params: { website: "", form_token: Rails.application.message_verifier("form_guard").generate(10.seconds.ago.to_f, purpose: "request:two-biz", expires_in: 1.day),
                                                  request_submission: { name: "Hannah Brooks", phone: "5550100100", address_line1: "1 Elm St", description: "Mowing" } }
    assert_redirected_to public_request_sent_path("two-biz")
  ensure
    Rails.cache = cache
  end

  test "in a lockdown the request form waits longer too" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    AbuseProtection.lockdown!(hours: 1)
    submit(form_token: token(at: 5.seconds.ago))
    assert_response :unprocessable_content
    assert_empty requests
    submit(form_token: token(at: 15.seconds.ago))
    assert_redirected_to public_request_sent_path("oakline")
  ensure
    Rails.cache = cache
  end

  test "a business takes at most #{PublicRequestsController::REQUESTS_PER_HOUR} requests an hour" do
    as_business(@business) do
      client = Client.create!(display_name: "Many", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      PublicRequestsController::REQUESTS_PER_HOUR.times { ServiceRequest.create!(client:, description: "x") }
    end
    submit
    assert_response :unprocessable_content
    assert_select ".banner-warning", /a lot of requests/
  end

  test "no acknowledgment until the business's owner has confirmed their account" do
    users(:one).update_columns(confirmed_at: nil)
    submit
    assert_redirected_to public_request_sent_path("oakline")
    follow_redirect!
    assert_select "p", { text: /emailed you/, count: 0 }
    assert_empty as_business(@business) { EmailMessage.where(to: "hannah@example.com").to_a }
  end

  test "a client with requests can't be deleted" do
    submit
    assert_not as_business(@business) { requests.sole.client.deletable? }
  end

  test "requests belong to their business" do
    submit
    request = requests.sole
    assert_raises(ActiveRecord::RecordNotFound) { as_business(businesses(:two)) { ServiceRequest.find(request.id) } }
  end

  test "the form is off until an Owner or Admin turns it on" do
    assert_not Business.create!(name: "Brand New", owner: users(:one)).request_form_enabled?
  end

  test "when the form is off, the page shows contact details and takes nothing" do
    @business.update!(request_form_enabled: false)
    get public_request_path("oakline")
    assert_select "form[action='/request/oakline']", false
    assert_select "a[href=?]", "tel:#{@business.phone}"
    submit
    assert_response :unprocessable_content
    assert_empty requests
  end

  test "unknown handles and suspended businesses aren't found" do
    get public_request_path("nobody-here")
    assert_response :not_found
    @business.update_columns(active: false)
    get public_request_path("oakline")
    assert_response :not_found
  end
end
