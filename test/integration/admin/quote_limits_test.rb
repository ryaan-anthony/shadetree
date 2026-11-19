require "test_helper"

# BIL-03: the plan's quote limit: a notice approaching it, one extra send at it, then new
# quotes wait (drafts keep working, resends never count); clients are never affected; the team
# size shows an upgrade prompt; a downgrade loses features, not data.
class Admin::QuoteLimitsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(email: "office@example.com")
    @owner = users(:one)
    @maria = as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def draft
    as_business(@business) do
      Quote.start(client: @maria).tap do |quote|
        quote.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
        quote.save!
      end
    end
  end

  def sent(count) = count.times.map { draft.tap { |quote| as_business(@business) { quote.mark_sent!(by: @owner, channel: "link") } } }

  test "approaching: a notice with usage and the reset date; owners see plans, admins are told to ask" do
    sent(4) # 80% of Free's 5
    quote = draft
    get edit_admin_quote_path(quote)
    assert_select "#quote-limit-notice.banner-info", /sent 4 of the 5 quotes your Free plan includes this period. It resets/
    assert_select "#quote-limit-notice a[href=?]", admin_plan_path
    get admin_root_path
    assert_select "#quote-limit-notice"

    sign_out :user
    admin = member_with_role("admin", business: @business)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get new_admin_quote_send_path(quote)
    assert_select "#quote-limit-notice", /Ask John about a bigger plan/
    assert_select "#quote-limit-notice a[href=?]", admin_plan_path, 0
  end

  test "at the limit one more goes out; then new quotes wait, drafts save, and resends still work" do
    first = sent(5).first
    extra = draft
    get new_admin_quote_send_path(extra)
    assert_select "#quote-limit-notice.banner-warning", /You can send one more/
    post admin_quote_send_path(extra), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { extra.reload.status }

    blocked = draft
    get new_admin_quote_send_path(blocked)
    assert_select "#quote-limit-notice", /and the one extra/
    assert_select "button[disabled]", /Get the link/
    post admin_quote_send_path(blocked), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(blocked)
    assert_match "used this period's quotes", flash[:alert]
    assert_equal "draft", as_business(@business) { blocked.reload.status }
    patch admin_quote_path(blocked), params: { quote: { title: "Still editable", lock_version: as_business(@business) { blocked.reload.lock_version } } }, as: :turbo_stream
    assert_equal "Still editable", as_business(@business) { blocked.reload.title }

    post admin_quote_send_path(first), params: { channel: "link" }
    assert_match "marked as sent", flash[:notice], "a quote already sent can be sent again"
    as_business(@business) { first.reload.revise!(by: @owner) }
    post admin_quote_send_path(first), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { first.reload.status }, "a revision of a sent quote doesn't count"

    @business.update!(plan: plans(:starter))
    post admin_quote_send_path(blocked), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { blocked.reload.status }, "a bigger plan lifts the limit at once"
  end

  test "clients are never stopped: viewing and approving a sent quote, and the request form, over the limit" do
    quote = sent(6).last
    link = as_business(@business) { quote.client_link! }
    sign_out :user
    get client_link_path(link.token)
    assert_response :success
    post approve_client_quote_path(link.token), params: { version: quote.lock_version, quote_response: { signer_name: "Maria Lopez", terms_accepted: "1" } }
    assert_equal "approved", as_business(@business) { quote.reload.status }
    @business.update!(request_form_enabled: true)
    get public_request_path(@business.handle)
    assert_response :success
  end

  test "the team size shows an upgrade prompt, not the invite form; members stay" do
    as_business(@business) { Invitation.create!(email: "new@example.com", role: "technician", invited_by: @owner) }
    get admin_team_path
    assert_select "#team-limit", /Free plan includes 2 team members/
    assert_select "#team-limit a[href=?]", admin_plan_path
    assert_select "form[action=?]", admin_invitations_path, 0
  end

  test "a downgrade turns features off but deletes nothing" do
    @business.update!(plan: plans(:starter))
    assert_not Branding.new(@business).show_powered_by?
    quotes = sent(8)
    @business.update!(plan: plans(:free))
    assert Branding.new(@business.reload).show_powered_by?
    assert_equal 8, as_business(@business) { Quote.where(id: quotes.map(&:id)).count }
    assert_equal :blocked, @business.entitlements.quote_sending
  end
end
