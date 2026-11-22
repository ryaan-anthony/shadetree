require "test_helper"

# CLI-05: the client timeline: each feature records its events as they happen, and the client
# page shows them newest first, a page at a time.
class Admin::ClientTimelineTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @maria = as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def kinds = as_business(@business) { @maria.events.timeline.map(&:kind) }

  test "requests, quotes, visits, invoices, payments, views and bounces are recorded and shown newest first" do
    as_business(@business) do
      request = ServiceRequest.create!(client: @maria, source: "form", description: "Leaves everywhere")
      quote = Quote.start(client: @maria)
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "200", "taxable" => "0" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "email")
      quote.client_link!.record_view!
      quote.record_response!(:approve, by: @owner, signer_name: "Maria Lopez", message: "On the phone")
      job = Job.find_by!(quote:)
      visit = job.visits.new(scheduled_on: @business.today, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
      visit.complete!(by: @owner)
      invoice = Invoice.from_job!(job, by: @owner)
      invoice.mark_sent!(by: @owner, channel: "link")
      invoice.record_payment!(by: @owner, amount: "50", received_on: @business.today, payment_method: "check", reference: "1042")
      invoice.record_payment!(by: @owner, amount: invoice.reload.balance, received_on: @business.today, payment_method: "cash")
      EmailMessage.create!(kind: "invoice_sent", to: "maria@example.com", related: invoice).mark!("bounced", error: "550")
      assert request
    end

    assert_equal %w[email_bounced invoice_paid payment_recorded payment_recorded invoice_sent visit_completed visit_scheduled
                    quote_approved quote_viewed quote_sent request_received], kinds

    get admin_client_path(@maria)
    assert_select "#client-timeline li", 11
    assert_select "#client-timeline", /Email not delivered\s*Invoice INV-\d+ to maria@example.com: The receiving mail server says this address doesn't exist.*Invoice INV-\d+ paid in full.*Payment: \$50\.00, check \(1042\), received .* on INV-\d+.*Invoice INV-\d+ sent as a link.*Visit done for J-\d+.*Visit booked for .*Approval of quote Q-\d+ recorded.*Maria Lopez opened quote Q-\d+.*Quote Q-\d+ sent by email.*Request received/m
    assert_no_match "maria@example.com refused", response.body
    assert_select "#client-timeline li", /Approval of quote Q-\d+ recorded.*#{@owner.full_name}/m
    assert_select "#client-timeline-more a", 0
  end

  test "long timelines load a page at a time" do
    as_business(@business) do
      30.times { |i| ClientEvent.record!(@maria, :visit_cancelled, when: "old#{i}", at: (40 - i).days.ago) }
    end
    get admin_client_path(@maria)
    assert_select "#client-timeline li", ClientEvent::PAGE_SIZE
    assert_select "#client-timeline li", /Visit on old29 cancelled/
    last = as_business(@business) { @maria.events.timeline.offset(ClientEvent::PAGE_SIZE - 1).first }
    assert_select "#client-timeline-more a[href=?]", timeline_admin_client_path(@maria, before: last.uid)

    get timeline_admin_client_path(@maria, before: last.uid), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal 5, response.body.scan("<li ").size
    assert_match "Visit on old0 cancelled", response.body
    assert_match %(<turbo-stream action="replace" target="client-timeline-more">), response.body
    assert_no_match "Show older", response.body
  end

  test "technicians can't see it; another business's client or event isn't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_client_path(@maria) }
    mine = as_business(@business) { ClientEvent.record!(@maria, :email_bounced) }
    assert_permission_matrix(technician: false) { get timeline_admin_client_path(@maria, before: mine.uid), headers: { "Accept" => "text/vnd.turbo-stream.html" } }

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs, their_event = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      [ client, ClientEvent.record!(client, :email_bounced) ]
    end
    assert_not_found_across_businesses { get timeline_admin_client_path(theirs, before: their_event.uid), headers: { "Accept" => "text/vnd.turbo-stream.html" } }
    assert_not_found_across_businesses { get timeline_admin_client_path(@maria, before: their_event.uid), headers: { "Accept" => "text/vnd.turbo-stream.html" } }
  end

  test "corrections show: a deleted payment, an invoice no longer paid, a reopened or moved or cancelled visit, a client's own answer" do
    as_business(@business) do
      quote = Quote.start(client: @maria)
      quote.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100", "taxable" => "0" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      quote.record_response!(:decline, link: quote.client_link!, message: "Too much")
      job = Job.create!(client: @maria, title: "Gutters", line_items_attributes: [ { name: "Gutters", quantity: 1, unit_price: "100" } ])
      first, second = 2.times.map { |i| job.visits.new(scheduled_on: @business.today + 1 + i, timing: "anytime") }
      Visit.schedule_all!([ first, second ], by: @owner, notify_client: false)
      first.reload.reschedule!({ scheduled_on: @business.today + 5 }, by: @owner, notify_client: false)
      second.reload.cancel!(by: @owner, notify_client: false)
      invoice = Invoice.start(client: @maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100", "taxable" => "0" } ])
      invoice.update!(tax_rates: [])
      payment = invoice.record_payment!(by: @owner, amount: "100", received_on: @business.today, payment_method: "cash")
      invoice.delete_payment!(payment, by: @owner, reason: "Wrong client")
    end
    assert_equal %w[invoice_unpaid payment_deleted invoice_paid payment_recorded invoice_sent visit_cancelled visit_scheduled visit_scheduled
                    quote_declined quote_sent], kinds

    get admin_client_path(@maria)
    assert_select "#client-timeline", /Invoice INV-\d+ no longer paid in full.*Payment deleted: \$100\.00, cash.*Payment: \$100\.00, cash, .*\(since deleted\).*Invoice INV-\d+ sent \(paid on the spot\).*Visit on .* cancelled.*since cancelled.*now .*Maria Lopez declined quote Q-\d+/m
  end

  test "a reissued link isn't a second first view; a plain GET of the next page goes back to the client" do
    as_business(@business) do
      quote = Quote.start(client: @maria)
      quote.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
      quote.save!
      quote.mark_sent!(by: @owner, channel: "link")
      link = quote.client_link!
      link.record_view!
      link.reissue!(by: @owner).record_view!
    end
    assert_equal 1, kinds.count("quote_viewed")
    event = as_business(@business) { @maria.events.first }
    get timeline_admin_client_path(@maria, before: event.uid)
    assert_redirected_to admin_client_path(@maria, anchor: "client-timeline")
  end
end
