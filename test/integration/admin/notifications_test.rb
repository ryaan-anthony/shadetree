require "test_helper"

# NTF-02: the notification center, email settings, and the features that raise notifications.
class Admin::NotificationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @quote = Quote.start(client: @maria).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180" } ])
        _1.save!
        _1.mark_sent!(by: @owner, channel: "link")
      end
    end
  end

  def sign_in_owner
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def notify(title = "Maria opened quote #{@quote.number}", kind: "quote_viewed")
    NotificationType.deliver(kind, business: @business, subject: @quote, title:, path: "/admin/quotes/#{@quote.uid}")
  end

  def mine(user = @owner) = as_business(@business) { Notification.for_user(user).recent.to_a }

  test "the bell shows the unread count, and the center lists only this member's, in this business" do
    other_admin = member_with_role(:admin)
    notify
    notify("Maria approved #{@quote.number}", kind: "quote_approved")
    NotificationType.deliver("quote_declined", business: businesses(:two), title: "Elsewhere", path: "/admin") # the owner is a technician there
    sign_in_owner
    get admin_quotes_path
    assert_select "a[href=?][aria-label='Notifications, 2 unread'] .notify-count", admin_notifications_path, "2"

    get admin_notifications_path
    assert_select "#notifications li", 2
    assert_select "#notifications", /Maria approved.*Maria opened/m
    assert_select "#notifications", { text: /Elsewhere/, count: 0 }
    assert_equal 2, mine(other_admin).size, "each member has their own copy"
  end

  test "opening one marks it read and goes there; hovering doesn't; one or all can be marked read" do
    notify
    notify("Second")
    sign_in_owner
    first, second = mine.reverse
    get open_admin_notification_path(first), headers: { "X-Sec-Purpose" => "prefetch" }
    assert_nil as_business(@business) { first.reload.read_at }
    get open_admin_notification_path(first)
    assert_redirected_to "/admin/quotes/#{@quote.uid}"
    assert as_business(@business) { first.reload.read? }

    patch read_admin_notification_path(second)
    assert as_business(@business) { second.reload.read? }
    notify("Third")
    patch read_all_admin_notifications_path
    assert mine.all?(&:read?)
    get admin_quotes_path
    assert_select ".notify-count", 0
  end

  test "another member's notification isn't found" do
    notify
    theirs = mine.first
    sign_in member_with_role(:admin)
    get open_admin_notification_path(theirs)
    assert_response :not_found
  end

  test "email settings per member: office types for Owners and Admins, nothing for Technicians yet" do
    sign_in_owner
    get settings_admin_notifications_path
    assert_select "input[name='email[]'][value=quote_approved][checked]"
    assert_select "input[name='email[]'][value=quote_viewed]:not([checked])"
    assert_select "input[name='email[]'][value=invitation_accepted]"

    patch settings_admin_notifications_path, params: { email: %w[quote_viewed] }
    membership = BusinessUser.find_by(business: @business, user: @owner)
    assert membership.email_notification?("quote_viewed")
    assert_not membership.email_notification?("quote_approved")

    sign_in member_with_role(:technician)
    get settings_admin_notifications_path
    assert_response :success
    assert_select "input[name='email[]']", 0
    get admin_notifications_path
    assert_response :success
  end

  test "a client's first open of a quote notifies the office once" do
    link = as_business(@business) { @quote.client_link! }
    get client_link_path(link.token)
    get client_link_path(link.token)
    viewed = as_business(@business) { Notification.where(kind: "quote_viewed").to_a }
    assert_equal [ @owner ], viewed.map(&:user)
    assert_equal "Maria Lopez opened quote #{@quote.number}", viewed.sole.title
  end

  test "a client's answer notifies the office, emailing those who want it" do
    link = as_business(@business) { @quote.client_link! }
    assert_enqueued_email_with QuoteActivityMailer, :responded, params: ->(params) { params[:user_id] == @owner.id } do
      post decline_client_quote_path(link.token), params: { version: as_business(@business) { @quote.reload.lock_version }, quote_response: { message: "Too pricey" } }
    end
    declined = as_business(@business) { Notification.find_by!(kind: "quote_declined") }
    assert_equal [ "Maria Lopez declined quote #{@quote.number}", "“Too pricey”", "/admin/quotes/#{@quote.uid}" ], [ declined.title, declined.body, declined.path ]
  end

  test "joining from an invitation notifies the people who manage the team" do
    invitation = as_business(@business) { Invitation.create!(email: "newbie@example.com", role: "technician", invited_by: @owner) }
    newbie = User.create!(email: "newbie@example.com", password: "password123", first_name: "Nia", last_name: "Ross", confirmed_at: Time.current)
    invitation.accept!(newbie)
    joined = as_business(@business) { Notification.find_by!(kind: "invitation_accepted") }
    assert_equal [ @owner, "Nia Ross joined as Technician", "/admin/team" ], [ joined.user, joined.title, joined.path ]
  end
end
