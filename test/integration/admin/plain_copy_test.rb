require "test_helper"

# #289 (admin UX review), copy and jargon: no internal codes where owners look, examples that
# fit the trade, phone numbers one way, plain labels and file names.
class Admin::PlainCopyTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    @maria = as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "2155551212" }, { kind: "email", value: "maria@example.com" } ])
    end
  end

  test "placeholders come from the business's trade, or stay neutral" do
    IndustryPreset.sync!
    @business.update!(industry: nil)
    quote = as_business(@business) { Quote.start(client: @maria).tap(&:save!) }
    get edit_admin_quote_path(quote)
    assert_select "input[name='quote[title]'][placeholder=?]", "e.g. Service call"
    get new_admin_service_request_path
    assert_no_match(/mowing/i, response.body)

    @business.update!(industry: "pest")
    get edit_admin_quote_path(quote)
    assert_select "input[name='quote[title]'][placeholder=?]", "e.g. General pest treatment"
    get new_admin_service_request_path
    assert_select "textarea[placeholder=?]", "e.g. Called about general pest treatment. Prefers mornings; use the side gate."
    get new_admin_catalog_item_path
    assert_select "input[name='catalog_item[name]'][placeholder=?]", "e.g. General pest treatment"
  end

  test "phone numbers are formatted one way on the client, the job and in settings" do
    @business.update!(phone: "2155551212")
    job = as_business(@business) { Job.create!(client: @maria, title: "Ants") }
    get admin_client_path(@maria)
    assert_select "a[href='tel:+12155551212']", "(215) 555-1212"
    get admin_job_path(job)
    assert_select "a[href='tel:+12155551212']", /\(215\) 555-1212/
    get edit_admin_business_path
    assert_select "input[name='business[phone]'][value=?]", "2155551212" # what's stored, not reformatted
  end

  test "saving settings keeps a phone number exactly as typed, wherever it's from" do
    patch admin_business_path, params: { business: { name: @business.name, phone: "0412 345 678 ext 2" } }
    assert_equal "0412 345 678 ext 2", @business.reload.phone
    get edit_admin_business_path
    assert_select "input[name='business[phone]'][value=?]", "0412 345 678 ext 2"
    patch admin_business_path, params: { business: { name: @business.name, phone: "0412 345 678 ext 2" } }
    assert_equal "0412 345 678 ext 2", @business.reload.phone, "saving again doesn't rewrite it"
  end

  test "a long file name with a dot in it doesn't break the quote builder" do
    quote = as_business(@business) do
      Quote.start(client: @maria).tap do |q|
        q.attachments.attach(io: StringIO.new("%PDF-1.4"), filename: "Estimate.Nov 20 2026 final copy for the Smith family", content_type: "application/pdf")
        q.save!
      end
    end
    get edit_admin_quote_path(quote)
    assert_response :success
    assert_select "a[aria-label=?]", "Estimate.Nov 20 2026 final copy for the Smith family", text: /\AEstimate\.Nov.*…th family\z/
  end

  test "a request names its services, and an approval that doesn't verify says so" do
    request = as_business(@business) { ServiceRequest.create!(client: @maria, source: "phone", description: "Bugs", services: %w[Ants Wasps Mice].map { { "name" => _1 } }) }
    assert_equal "Request for Ants and 2 more", request.title
    assert_equal "Request", as_business(@business) { ServiceRequest.new(services: []).title }

    quote = as_business(@business) do
      Quote.start(client: @maria).tap do |q|
        q.sync_line_items([ { "key" => "a", "name" => "Spraying", "quantity" => "1", "unit_price" => "80" } ]) && q.save!
        q.mark_sent!(by: @owner, channel: "link")
        q.record_response!(:approve, by: @owner, signer_name: "Maria", message: "On the phone")
        QuoteResponse.where(id: q.reload.approval.id).update_all(signature: "tampered") # as if changed in the database
      end
    end
    get admin_quote_path(quote)
    assert_select "p.text-danger", "This approval record doesn't verify."
  end

  test "approval evidence sits behind 'Reference'; no version number for owners" do
    quote = as_business(@business) do
      Quote.start(client: @maria).tap do |q|
        q.sync_line_items([ { "key" => "a", "name" => "Spraying", "quantity" => "1", "unit_price" => "80" } ]) && q.save!
        q.mark_sent!(by: @owner, channel: "link")
        q.record_response!(:approve, by: @owner, signer_name: "Maria", message: "On the phone")
      end
    end
    get admin_quote_path(quote)
    assert_no_match(/Quote version/, response.body)
    assert_select "details summary", "Reference"
    assert_select "details", /Approval #{as_business(@business) { quote.reload.approval.reference }}/
  end

  test "plain labels: jobs filters, documents' days, hours preset, services" do
    get admin_jobs_path
    assert_select "button[name=filter][value=open]", /Not finished/
    get admin_jobs_path(filter: "to_invoice") # PLT-19: a tab at 0 shows only when it's the current one
    assert_select "button[name=filter][value=to_invoice]", /Ready to invoice/
    get edit_admin_business_path(tab: "documents")
    assert_select "label", /Days a quote stays valid/
    assert_select "label", /Days to pay, after it's issued/
    get admin_hours_path
    assert_select "button", "Set Mon–Fri, 8 am–5 pm"
    get admin_catalog_items_path
    assert_select "h1", "Services & prices"
    assert_select "a", "Add starter services"
  end
end
