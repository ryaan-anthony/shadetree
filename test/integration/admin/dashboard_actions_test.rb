require "test_helper"

# INS-01: the action dashboard: each group's inclusion rules and order, today's visits by
# person, the month's summary, role routing and tenancy.
class Admin::DashboardActionsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", onboarded_at: Time.current)
    @owner = users(:one)
    @today = @business.today
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def client(name) = Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: "555010#{name.length.to_s.rjust(2, "0")}00" } ])

  def quote(client, status:, sent: nil)
    Quote.start(client:).tap do |quote|
      quote.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
      quote.save!
      quote.update_columns(status:, sent_at: sent)
    end
  end

  test "each group lists only what needs doing, oldest first, with counts and links" do
    as_business(@business) do
      @maria, @sam = client("Maria Lopez"), client("Sam Okafor")
      ServiceRequest.create!(client: @maria, source: "form", description: "Leaves")
      ServiceRequest.create!(client: @sam, source: "form", description: "Old one").update_columns(status: "archived")
      @changes = quote(@maria, status: "changes_requested")
      @old_sent = quote(@maria, status: "sent", sent: 10.days.ago)
      @new_sent = quote(@sam, status: "sent", sent: 1.day.ago)
      quote(@sam, status: "sent", sent: 2.days.ago).update_columns(archived_at: Time.current)
      quote(@sam, status: "draft")
      @unscheduled = Job.create!(client: @maria, title: "Gutters")
      @done = Job.create!(client: @sam, title: "Aeration").tap { _1.complete!(by: @owner) }
      billed = Job.create!(client: @sam, title: "Billed").tap { _1.complete!(by: @owner) }
      Invoice.from_job!(billed)
      voided = Job.create!(client: @sam, title: "Voided bill").tap { _1.complete!(by: @owner) }
      Invoice.from_job!(voided).update_columns(status: "void")
      @late = Invoice.start(client: @maria).tap { _1.update_columns(status: "sent", sent_at: 1.month.ago, issued_on: @today - 40, due_on: @today - 10, total_cents: 5_000) }
      Invoice.start(client: @sam).tap { _1.update_columns(status: "sent", sent_at: 1.day.ago, issued_on: @today, due_on: @today + 10, total_cents: 5_000) }
      Invoice.start(client: @sam).tap { _1.update_columns(status: "paid", sent_at: 1.month.ago, issued_on: @today - 40, due_on: @today - 10) }
    end

    get admin_root_path
    assert_response :success
    assert_select "#group-new_requests li", 1
    assert_select "#group-changes_requested li", /#{@changes.number}/
    assert_select "#group-awaiting_answer li", 2
    assert_select "#group-awaiting_answer li:first-child", /#{@old_sent.number}.*Sent 10 days ago/m
    assert_select "#group-awaiting_answer a[href=?]", admin_quotes_path(filter: "awaiting")
    assert_select "#group-to_schedule li", /#{@unscheduled.number}/
    assert_select "#group-to_invoice li", 2
    assert_select "#group-to_invoice", /#{@done.number}/
    assert_select "#group-to_invoice", text: /Billed/, count: 0
    assert_select "#group-overdue li", 1
    assert_select "#group-overdue li", /#{@late.number}.*\$50\.00, 10 days late/m
  end

  test "groups show the top five and a count; empty groups collapse and an empty dashboard says what's next" do
    get admin_root_path
    assert_select "[id^=group-]", 0
    assert_select ".empty-state, [class*=empty]", /all caught up/
    as_business(@business) { maria = client("Maria Lopez"); 7.times { |i| quote(maria, status: "sent", sent: (i + 1).days.ago) } }
    get admin_root_path
    assert_select "#group-awaiting_answer li", 5
    assert_select "#group-awaiting_answer a", /See all 7/
    assert_select "[id^=group-]", 1
  end

  test "today's visits, by the people on them; the month's quotes sent, approval rate and payments" do
    tech = users(:two)
    BusinessUser.find_or_create_by!(user: tech, business: @business) { _1.role = "technician"; _1.active = true }
    as_business(@business) do
      maria = client("Maria Lopez")
      job = Job.create!(client: maria, title: "Mowing")
      job.visits.new(scheduled_on: @today, timing: "anytime", assignee_ids: [ tech.id ]).schedule!(by: @owner, notify_client: false)
      job.visits.new(scheduled_on: @today, timing: "anytime").schedule!(by: @owner, notify_client: false)
      job.visits.new(scheduled_on: @today + 1, timing: "anytime", assignee_ids: [ tech.id ]).schedule!(by: @owner, notify_client: false)

      2.times do
        q = quote(maria, status: "draft")
        q.mark_sent!(by: @owner, channel: "link")
      end
      Quote.where(status: "sent").first.record_response!(:approve, by: @owner, signer_name: "Maria", message: "Phone")
      Quote.where(status: "sent").first.record_response!(:decline, by: @owner, message: "No")
      invoice = Invoice.start(client: maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "300" } ])
      invoice.update!(tax_rates: [])
      invoice.record_payment!(by: @owner, amount: "120", received_on: @today, payment_method: "cash")
    end
    get admin_root_path
    assert_select "#todays-visits", /2 visits/
    assert_select "#todays-visits section", 2
    assert_select "#todays-visits section:first-child h3", tech.full_name
    assert_select "#todays-visits section:last-child h3", "Not assigned"
    assert_select "#month-summary", /Quotes sent this month\s*2.*Approval rate\s*50%.*Payments received\s*\$120\.00/m
  end

  test "technicians land on their day; another business's work never shows" do
    sign_out :user
    tech = member_with_role("technician", business: @business)
    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_redirected_to admin_my_day_path

    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    as_business(businesses(:two)) { quote(client("Theirs Inc"), status: "changes_requested") }
    get admin_root_path
    assert_select "#group-changes_requested", 0
  end

  test "a busy business's dashboard takes a fixed number of queries" do
    count = lambda do
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_root_path }
      queries
    end
    as_business(@business) { maria = client("Maria Lopez"); 3.times { |i| quote(maria, status: "sent", sent: (i + 1).days.ago) } }
    few = count.call
    as_business(@business) do
      sam = client("Sam Okafor")
      20.times { |i| quote(sam, status: "sent", sent: (i + 1).days.ago) }
      10.times { |i| Job.create!(client: sam, title: "Job #{i}").visits.new(scheduled_on: @today, timing: "anytime", assignee_ids: [ @owner.id ]).schedule!(by: @owner, notify_client: false) }
    end
    assert_operator count.call, :<=, few + 6, "more records mustn't mean more queries"
  end
end
