require "test_helper"

# BIL-01: Settings → Plan, and the gates wired to plans: the team size on invitations, and the
# number of free businesses one person may own.
class Admin::PlanSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "the plan page shows the plan, what's used and included, and the other plans; only for settings people" do
    get admin_plan_path
    assert_response :success
    assert_select "#current-plan", /You're on Free/
    assert_select "#limit-team_members", /1 of 2/
    assert_select "#limit-quotes_sent", /0 of 5/
    assert_select "#compare-plans th", /Starter.*\$19\.00\/month/m
    assert_select "#compare-plans th", /Free \(yours\)/
    assert_select "#compare-plans td", /Unlimited/

    plans(:starter).update!(public: false)
    @business.update!(plan: plans(:starter))
    get admin_plan_path
    assert_select "#compare-plans th", /Starter \(yours\)/, "a hidden plan the business is on still shows"
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_plan_path }
  end

  test "invitations stop at the plan's team size, counting pending ones" do
    post admin_invitations_path, params: { invitation: { email: "first@example.com", role: "technician" } }
    assert_match "Invitation sent", flash[:notice]
    post admin_invitations_path, params: { invitation: { email: "second@example.com", role: "technician" } }
    assert_match "Your Free plan includes 2 people, counting you and pending invitations. Revoke an invitation", flash[:alert]
    @business.update!(plan_overrides: { "limits" => { "team_members" => 5 } })
    post admin_invitations_path, params: { invitation: { email: "second@example.com", role: "technician" } }
    assert_match "Invitation sent", flash[:notice]
  end

  test "one person may own three businesses on the free plan" do
    2.times { |i| Business.create!(owner: @owner, name: "Shop #{i}", industry: "landscaping", timezone: "America/New_York") }
    post admin_business_path, params: { business: { name: "Fourth", industry: "landscaping", timezone: "America/New_York" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /already own 3 businesses on the free plan/
    assert_raises(ActiveRecord::RecordInvalid) { Business.create!(owner: @owner, name: "Sneaky", industry: "landscaping", timezone: "America/New_York") }
    @owner.owned_businesses.where.not(id: @business.id).first.update!(plan: plans(:starter))
    post admin_business_path, params: { business: { name: "Fourth", industry: "landscaping", timezone: "America/New_York" } }
    assert_redirected_to admin_root_path
  end

  test "usage shows on the plan page with the reset date, by the send action, and on the dashboard" do
    travel_to Time.utc(2026, 11, 18, 15) do
      get admin_plan_path
      assert_select "#usage-resets", /resets on Dec 1, 2026/
      quote = as_business(@business) do
        client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
        Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ]) && _1.save! }
      end
      as_business(@business) { quote.mark_sent!(by: @owner, channel: "link") }
      draft = as_business(@business) { Quote.start(client: quote.client).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ]) && _1.save! } }
      get edit_admin_quote_path(draft)
      assert_select "#quote-usage", /1 of 5 quotes sent/
      get new_admin_quote_send_path(draft)
      assert_select "#quote-usage", /1 of 5 quotes sent/
      get admin_root_path
      assert_select "#quotes-sent-usage", /1\s*of 5/
      as_business(@business) { quote.reload.revise!(by: @owner) }
      get edit_admin_quote_path(quote)
      assert_select "#quote-usage", 0, "a revision's send doesn't count"
      @business.update!(plan: plans(:business))
      get edit_admin_quote_path(draft)
      assert_select "#quote-usage", 0, "no limit, no indicator"
    end
  end

  test "reactivating a member or resending an expired invitation can't go past the team size" do
    member = member_with_role("technician", business: @business)
    membership = as_business(@business) { BusinessUser.find_by!(user: member) }
    as_business(@business) { membership.update!(active: false, deactivated_at: Time.current) }
    expired = as_business(@business) { Invitation.create!(email: "late@example.com", role: "technician", invited_by: @owner).tap { _1.update_columns(expires_at: 1.day.ago) } }
    as_business(@business) { Invitation.create!(email: "now@example.com", role: "technician", invited_by: @owner) }
    patch reactivate_admin_member_path(membership)
    assert_match "includes 2 people", flash[:alert]
    assert_not as_business(@business) { membership.reload.active? }
    post resend_admin_invitation_path(expired)
    assert_match "includes 2 people", flash[:alert]
    assert as_business(@business) { expired.reload.expires_at.past? }
  end

  test "a paid plan hides Powered by Shadetree on client pages and emails" do
    quote = as_business(@business) do
      client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ]) && _1.save! && _1.update_column(:status, "sent") }
    end
    link = as_business(@business) { quote.client_link! }
    get client_link_path(link.token)
    assert_select "footer", /Powered by\s*Shadetree/
    @business.update!(plan: plans(:starter))
    get client_link_path(link.token)
    assert_select "footer", text: /Powered by/, count: 0
    mail = ClientMailer.with(business_id: @business.id, to: "maria@example.com", recipient_name: "Maria").test_message
    assert_no_match "Sent with", mail.html_part.body.to_s
    @business.update!(plan: plans(:free))
    mail = ClientMailer.with(business_id: @business.id, to: "maria@example.com", recipient_name: "Maria").test_message
    assert_match "Sent with", mail.text_part.body.to_s
  end
end
