require "test_helper"

# BIL-03: the plan's quote limit: a notice approaching it; at it, new quotes wait with no
# grace send (drafts keep working, resends and revisions never count); clients are never affected; the team
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
    assert_select "#quote-limit-notice.banner-warning", /sent 4 of the 5 quotes your Free plan includes this period. You can send 1 more before your count resets on/
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

  test "below the limit the last one goes out; at it new quotes wait, drafts save, and resends still work" do
    first = sent(4).first
    last = draft
    post admin_quote_send_path(last), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { last.reload.status }, "the 5th of 5 goes out"

    blocked = draft
    get new_admin_quote_send_path(blocked)
    assert_select "#quote-limit-notice.banner-danger", /You've used the 5 quotes your Free plan includes this period. New quotes can be sent again on/
    assert_select "#quote-limit-notice", text: /one more|extra/, count: 0
    assert_select "form[action=?]", admin_quote_send_path(blocked), 0, "the send options give way to the explanation"
    post admin_quote_send_path(blocked), params: { channel: "link" }
    assert_redirected_to new_admin_quote_send_path(blocked)
    assert_match "used this period's quotes", flash[:alert]
    assert_equal "draft", as_business(@business) { blocked.reload.status }
    patch admin_quote_path(blocked), params: { quote: { title: "Still editable", lock_version: as_business(@business) { blocked.reload.lock_version } } }, as: :turbo_stream
    assert_equal "Still editable", as_business(@business) { blocked.reload.title }

    post admin_quote_send_path(first), params: { channel: "link" }
    assert_match "marked as sent", flash[:notice], "a quote already sent can be sent again"
    as_business(@business) { first.reload.revise!(by: @owner) }
    get new_admin_quote_send_path(first)
    assert_select "form[action=?]", admin_quote_send_path(first), { minimum: 1 }, "a revision keeps its send options at the limit"
    post admin_quote_send_path(first), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { first.reload.status }, "a revision of a sent quote goes out at the limit"
    assert_equal [ 5, :blocked ], as_business(@business) { [ Entitlements.for(@business).used(:quotes_sent), Entitlements.for(@business).quote_sending ] }, "and doesn't count"

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
    assert_select "#team-limit", /Free plan includes 2 people, counting you and pending invitations\..*See plans.*or revoke an invitation/m
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

  test "admins at the limit are told to ask; technicians never see the notice" do
    sent(6)
    admin = member_with_role("admin", business: @business)
    sign_out :user
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get edit_admin_quote_path(draft)
    assert_select "#quote-limit-notice", /sent 6 quotes this period; your Free plan includes 5\..*Ask John about a bigger plan/m
    sign_out :user
    tech = member_with_role("technician", business: @business)
    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    assert_select "#quote-limit-notice", 0
  end

  test "a limit of 0 allows no sends; two first sends at the boundary can't both get the last one" do
    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => 0 } })
    quote = draft
    get new_admin_quote_send_path(quote)
    assert_select "#quote-limit-notice", /doesn't include sending quotes/
    post admin_quote_send_path(quote), params: { channel: "link" }
    assert_equal "draft", as_business(@business) { quote.reload.status }

    @business.update!(plan_overrides: {})
    sent(4)
    first, second = draft, draft
    # Both pass the page's check; the second is refused inside its send.
    post admin_quote_send_path(first), params: { channel: "link" }
    # Only the page's check is skipped, for this one request; the callback chain is untouched.
    Admin::QuoteSendsController.class_eval { alias_method :original_require_quote_allowance, :require_quote_allowance; define_method(:require_quote_allowance) { nil } }
    begin
      post admin_quote_send_path(second), params: { channel: "link" }
    ensure
      Admin::QuoteSendsController.class_eval { alias_method :require_quote_allowance, :original_require_quote_allowance; remove_method :original_require_quote_allowance }
    end
    assert_match "used this period's quotes", flash[:alert]
    assert_equal [ "sent", "draft" ], as_business(@business) { [ first.reload.status, second.reload.status ] }
  end

  test "the warning from 80% stays; an unlimited plan never sees a notice or a refusal" do
    sent(3)
    get admin_root_path
    assert_select "#quote-limit-notice", 0, "60% is below the warning"
    sent(1)
    get admin_root_path
    assert_select "#quote-limit-notice.banner-warning", /sent 4 of the 5 quotes/

    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => 10 } })
    sent(4)
    get admin_root_path
    assert_select "#quote-limit-notice.banner-warning", /sent 8 of the 10 quotes.*You can send 2 more before/m, "from 80%, how many are left"
    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => 2 } })
    as_business(@business) { UsageEvent.delete_all }
    get admin_root_path
    assert_select "#quote-limit-notice", 0, "nothing sent of 2"
    sent(1)
    get admin_root_path
    assert_select "#quote-limit-notice.banner-warning", /You can send 1 more before your count resets/, "a small limit still warns with one left"
    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => 1 } })
    as_business(@business) { UsageEvent.delete_all }
    get admin_root_path
    assert_select "#quote-limit-notice.banner-warning", /Your Free plan includes 1 quote this period. You can send 1 before your count resets/

    @business.update!(plan_overrides: { "limits" => { "quotes_sent" => nil } })
    sent(6)
    quote = draft
    get new_admin_quote_send_path(quote)
    assert_select "#quote-limit-notice", 0
    post admin_quote_send_path(quote), params: { channel: "link" }
    assert_equal "sent", as_business(@business) { quote.reload.status }
  end

  test "over the limit, clients still pay invoices and see their visits" do
    sent(6)
    invoice, visit_job = as_business(@business) do
      invoice = Invoice.start(client: @maria)
      invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
      invoice.update!(tax_rates: [])
      invoice.mark_sent!(by: @owner, channel: "link")
      [ invoice, Job.create!(client: @maria, title: "Mowing") ]
    end
    link = as_business(@business) { invoice.client_link! }
    sign_out :user
    get client_link_path(link.token)
    assert_response :success
    assert_select ".client-card", /Amount due/
    assert visit_job
  end
end
