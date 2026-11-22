require "test_helper"

# Simulates an autosave committing after the send's checks but before its transaction (QTE-08).
module LateAutosave
  mattr_accessor :hook
  def valid?(...) = super.tap { LateAutosave.hook&.call }
end
QuoteSendForm.prepend(LateAutosave)

# QTE-08: a built-in Technician (quotes their requests, doesn't send their own) sends a draft of
# only services marked "Technicians can send without review", at their prices; anything else
# goes to Ready for review with the reason.
class Admin::SendWithoutReviewTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15)
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", email: "office@example.com", plan_overrides: { "limits" => { "team_members" => nil } })
    @owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    as_business(@business) do
      @gutters = CatalogItem.create!(name: "Gutter clean", unit: "visit", unit_price: "150", send_without_review: true)
      @design = CatalogItem.create!(name: "Garden design", unit: "hour", unit_price: "90")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @request_record = ServiceRequest.create!(client: @maria, source: "phone", description: "Gutters",
                                               services: [ { "catalog_item_id" => @gutters.id, "name" => "Gutter clean" } ])
      RequestFollowUp.assign!(@request_record, { user: @tech, scheduled_on: Date.new(2026, 11, 23) }, by: @owner).done!(by: @tech)
    end
    sign_in_as @tech
    post quote_admin_my_request_path(@request_record)
    @quote = as_business(@business) { Quote.order(:id).last }
  end

  teardown { LateAutosave.hook = nil }

  def sign_in_as(user, business: @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def autosave(**line)
    key, version = as_business(@business) { [ @quote.line_items.reload.first&.key || "k1", @quote.reload.lock_version ] }
    row = { key:, catalog_item: @gutters.uid, name: "Gutter clean", unit: "visit", unit_price: "150", quantity: "1", taxable: "1" }.merge(line)
    patch admin_quote_path(@quote), params: { quote: { lock_version: version, lines_present: "1", lines: { "0" => row } } }, as: :turbo_stream
  end

  def email_it(to: "maria@example.com", **params)
    post admin_quote_send_path(@quote), params: { quote_send: { to:, subject: "Your quote", message: "Hi" }, **params }
  end

  def status = as_business(@business) { @quote.reload.status }

  test "a qualifying draft: Send quote beside Ready for review; it goes to the client's email, counts, and the history says why" do
    get edit_admin_quote_path(@quote)
    assert_select "#review-state a#send-without-review[href=?]", new_admin_quote_send_path(@quote), /Send quote/
    assert_select "#review-state button[form=ready-for-review-form]", /Ready for review/
    get new_admin_quote_send_path(@quote)
    assert_response :success

    email_it(to: "someone@else.example")
    assert_select "[role=alert]", /email on file/
    assert_equal "draft", status
    assert_difference -> { as_business(@business) { UsageEvent.count } }, 1 do
      email_it(quote_send: { to: "maria@example.com", subject: "Gutters, Thursday", message: "Edited wording" })
    end
    assert_redirected_to admin_root_path
    as_business(@business) do
      @quote.reload
      assert_equal [ "sent", @tech ], [ @quote.status, @quote.sent_by ]
      event = @quote.events.sole
      assert_equal [ "sent_without_review", @tech ], [ event.kind, event.user ]
      assert_equal({ "services" => [ "Gutter clean" ], "total" => "$150.00", "cap" => nil }, event.data)
    end

    sign_in_as @owner
    get admin_quote_path(@quote)
    assert_select "main", /Sent without review by Marcus Reyes/
    assert_select "main", /Only services technicians can send without review, at their prices: Gutter clean. Total \$150.00./
  end

  test "the copy link works too" do
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "sent", status
    assert_equal [ "sent_without_review" ], as_business(@business) { @quote.events.map(&:kind) }
  end

  test "a draft that doesn't qualify: only Ready for review, the reason, and the send is refused" do
    autosave(unit_price: "140")
    assert_select "turbo-stream[target=review-state] template", html: /Ready for review/
    assert_no_match(/send-without-review/, response.body)
    assert_select "turbo-stream[target=without-review] template", html: /Gutter clean: price changed/
    get edit_admin_quote_path(@quote)
    assert_select "#send-without-review", 0
    assert_select "#review-reason", /Needs the office's review: Gutter clean: price changed/

    get new_admin_quote_send_path(@quote)
    assert_redirected_to edit_admin_quote_path(@quote)
    assert_equal "This quote needs the office's review (Gutter clean: price changed). Mark it ready for review instead.", flash[:alert]
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "draft", status

    autosave(unit_price: "150")
    assert_select "turbo-stream[target=review-state] template", html: /send-without-review/
    post ready_admin_quote_path(@quote), params: { lock_version: as_business(@business) { @quote.reload.lock_version } }
    assert as_business(@business) { @quote.reload.ready_for_review? }, "they can still hand it over"
  end

  test "rechecked inside the send: a change saved after the page's checks stops it" do
    LateAutosave.hook = -> { as_business(@business) { @quote.line_items.first.update_columns(unit_price_cents: 9_900) } }
    email_it
    assert_redirected_to edit_admin_quote_path(@quote)
    assert_match "Gutter clean: price changed", flash[:alert]
    assert_equal "draft", status
    assert_equal 0, as_business(@business) { UsageEvent.count }
  end

  test "the cap, tax included, and a $0.00 quote after the usual confirmation" do
    @business.update!(without_review_cap: "100")
    get edit_admin_quote_path(@quote)
    assert_select "#review-reason", /Over \$100.00/
    @business.update!(without_review_cap: "150")
    autosave(quantity: "0")
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(@quote)
    assert_equal "draft", status
    post admin_quote_send_path(@quote), params: { channel: "link", zero_total: "confirmed" }
    assert_equal "sent", status
  end

  test "no grace send: at the limit it's blocked, they're told to ask the owner, and can mark it ready" do
    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => 1, "team_members" => nil } })
    get edit_admin_quote_path(@quote)
    assert_select "#send-without-review", 1, "one left still sends"
    as_business(@business) do
      other = Quote.start(client: @maria)
      other.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "10" } ]) && other.save!
      other.mark_sent!(by: @owner, channel: "link")
    end
    get edit_admin_quote_path(@quote)
    assert_select "#send-without-review", 0
    assert_select "#quote-limit-notice", /Ask John about a bigger plan/
    assert_select "#review-state button", /Ready for review/
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_redirected_to edit_admin_quote_path(@quote)
    assert_match "Ask John about a bigger plan, or mark it ready for review.", flash[:alert]
    assert_equal "draft", status
  end

  test "without a confirmed email: the office's notice, and Ready for review" do
    @tech.update_columns(confirmed_at: nil)
    get edit_admin_quote_path(@quote)
    assert_select "#send-without-review", 0
    assert_select "#confirm-to-send", /Confirm your email address before sending anything to clients/
    assert_select "#review-state button", /Ready for review/
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "draft", status
  end

  test "roles: only members who quote requests and don't send their own; never a revision; the office is unaffected" do
    crew = as_business(@business) { Role.create!(name: "Crew", permissions: %w[field_work]) }
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    @business.business_users.find_by!(user: @tech).update!(role: "custom", role_id: crew.id)
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_response :forbidden
    @business.business_users.find_by!(user: @tech).update!(role: "technician", role_id: nil)

    as_business(@business) { @quote.update_columns(revision: 2) }
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_response :not_found
    as_business(@business) { @quote.update_columns(revision: 1) }

    sign_in_as @owner
    autosave(unit_price: "99")
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "sent", status, "the office sends anything"
    assert_empty as_business(@business) { @quote.events.to_a }, "and it isn't a send without review"
  end

  test "another business's service, even one marked to send without review, is only a custom line here" do
    theirs = as_business(businesses(:two)) { CatalogItem.create!(name: "Gutter clean", unit: "visit", unit_price: "150", send_without_review: true) }
    autosave(catalog_item: theirs.uid)
    assert_select "turbo-stream[target=without-review] template", html: /Gutter clean: custom line/
    post admin_quote_send_path(@quote), params: { channel: "link" }
    assert_equal "draft", status
  end

  test "another business's technician never reaches it" do
    other = User.create!(email: "tech2@example.com", password: "password123", first_name: "Ann", confirmed_at: Time.current)
    BusinessUser.create!(user: other, business: businesses(:two), role: "technician")
    sign_in_as other, business: businesses(:two)
    assert_not_found_across_businesses { get new_admin_quote_send_path(@quote) }
    assert_not_found_across_businesses { post admin_quote_send_path(@quote), params: { channel: "link" } }
    assert_equal "draft", status
  end
end
