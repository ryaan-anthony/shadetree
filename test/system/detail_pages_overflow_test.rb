require "application_system_test_case"

# #412: a long address or property label wraps inside its card, so no detail page scrolls
# sideways on a phone (390 px). The staff invoice page doesn't show the property; it's checked
# for the same layout all the same.
class DetailPagesOverflowTest < ApplicationSystemTestCase
  LABEL = "Northwesternmostcornerlotbehindthegreenhouseandthelongbarn" # 58 characters, no breaks
  STREET = "#{"1234567890" * 10} Longstreet"
  CITY = "Llanfairpwllgwyngyllgogerychwyrndrobwllllantysiliogogogoch"

  setup do
    @business = businesses(:one)
    @user = users(:one)
    @paths = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ],
                              properties_attributes: [ { label: LABEL, address_line1: STREET, city: CITY, region: "NC", postal_code: "28801", billing: true } ])
      property = client.properties.first
      request = ServiceRequest.create!(client:, property:, source: "phone", description: "Gutters")
      quote = request.create_quote!(by: @user)
      quote.sync_line_items([ { "key" => "a", "name" => "Gutter clean", "unit" => "visit", "unit_price" => "140", "quantity" => "1" } ])
      quote.save!
      quote.mark_sent!(by: @user, channel: "link")
      job = Job.create!(client:, property:, title: "Ants", line_items_attributes: [ { name: "Spraying", quantity: 1, unit_price: 40 } ])
      job.complete!(by: @user)
      invoice = Invoice.from_job!(job, by: @user).tap { _1.mark_sent!(by: @user, channel: "link") }
      [ admin_client_path(client), admin_quote_path(quote), admin_job_path(job), admin_invoice_path(invoice), admin_service_request_path(request) ]
    end
    visit new_user_session_path
    sign_in_with_form(@user.email, "password123")
    assert_text "Home"
  end

  test "the client, quote, job, invoice and request pages don't scroll sideways at 390 px" do
    page.current_window.resize_to(390, 844)
    @paths.each do |path|
      visit path
      assert_text "Maria Lopez" # the page has loaded
      width, viewport = evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")
      assert_operator width, :<=, viewport, "#{path} is #{width} px wide in a #{viewport} px window"
    end
  ensure
    page.current_window.resize_to(1400, 1400) # the browser is shared: later tests expect desktop width
  end
end
