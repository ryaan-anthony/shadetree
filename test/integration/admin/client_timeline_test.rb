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
    assert_select "#client-timeline", /Email to maria@example.com refused by the mail server.*Invoice INV-\d+ paid in full.*Payment: \$50\.00, check \(1042\), received .* on INV-\d+.*Invoice INV-\d+ sent as a link.*Visit done for J-\d+.*Visit booked for .*Quote Q-\d+ approved.*Opened quote Q-\d+.*Quote Q-\d+ sent by email.*Request R-\w+ received/m
    assert_select "#client-timeline", /Dana|#{@owner.full_name}/
    assert_select "#client-timeline-more a", 0
  end

  test "long timelines load a page at a time" do
    as_business(@business) do
      30.times { |i| ClientEvent.record!(@maria, :email_bounced, to: "old#{i}@example.com", at: (40 - i).days.ago) }
    end
    get admin_client_path(@maria)
    assert_select "#client-timeline li", ClientEvent::PAGE_SIZE
    assert_select "#client-timeline li", /old29@example.com/
    last = as_business(@business) { @maria.events.timeline.offset(ClientEvent::PAGE_SIZE - 1).first }
    assert_select "#client-timeline-more a[href=?]", timeline_admin_client_path(@maria, before: last.id)

    get timeline_admin_client_path(@maria, before: last.id), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal 5, response.body.scan("<li ").size
    assert_match "old0@example.com", response.body
    assert_match %(<turbo-stream action="replace" target="client-timeline-more">), response.body
    assert_no_match "Show older", response.body
  end

  test "technicians can't see it; another business's client or event isn't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_client_path(@maria) }
    mine = as_business(@business) { ClientEvent.record!(@maria, :email_bounced, to: "a@example.com") }
    assert_permission_matrix(technician: false) { get timeline_admin_client_path(@maria, before: mine.id), headers: { "Accept" => "text/vnd.turbo-stream.html" } }

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs, their_event = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      [ client, ClientEvent.record!(client, :email_bounced, to: "t@example.com") ]
    end
    assert_not_found_across_businesses { get timeline_admin_client_path(theirs, before: their_event.id), headers: { "Accept" => "text/vnd.turbo-stream.html" } }
    assert_not_found_across_businesses { get timeline_admin_client_path(@maria, before: their_event.id), headers: { "Accept" => "text/vnd.turbo-stream.html" } }
  end
end
