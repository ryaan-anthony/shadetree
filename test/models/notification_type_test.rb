require "test_helper"

# NTF-02: the shared mechanism: who gets a notification, who also gets the email, and pruning.
class NotificationTypeTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include PermissionHelpers # member_with_role

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @admin = member_with_role(:admin)
    @tech = member_with_role(:technician)
    @unconfirmed_admin = member_with_role(:admin).tap { _1.update_columns(confirmed_at: nil) }
  end

  def deliver(kind = "quote_viewed", **options)
    NotificationType.deliver(kind, business: @business, title: "Maria opened quote Q-0001", path: "/admin/quotes/abc", **options)
  end

  def notified(kind = nil) = as_business(@business) { (kind ? Notification.where(kind:) : Notification.all).map(&:user) }

  test "office types reach active Owners and Admins, not Technicians or the person who did it" do
    deliver("quote_approved", actor: @admin)
    assert_equal [ @owner, @unconfirmed_admin ].map(&:id).sort, notified.map(&:id).sort
    BusinessUser.find_by(business: @business, user: @unconfirmed_admin).update!(active: false)
    deliver("quote_declined")
    assert_equal [ @owner, @admin ].map(&:id).sort, notified("quote_declined").map(&:id).sort
  end

  test "email follows each member's choice or the type's default, and only to confirmed accounts" do
    assert_enqueued_emails 0 do
      deliver("quote_viewed") # off by default
    end
    BusinessUser.find_by(business: @business, user: @admin).update!(notification_emails: { "quote_viewed" => true })
    assert_enqueued_email_with NotificationMailer, :notice, params: ->(params) { params[:business_id] == @business.id } do
      deliver("quote_viewed")
    end
    assert_enqueued_emails 2 do # owner and admin by default; the unconfirmed admin gets none
      deliver("quote_approved")
    end
    BusinessUser.find_by(business: @business, user: @owner).update!(notification_emails: { "quote_approved" => false })
    assert_enqueued_emails 1 do
      deliver("quote_approved")
    end
  end

  test "a type's own email is used when given, and the generic one says what and where" do
    mails = []
    deliver("quote_approved", email: ->(user) { mails << user.email; NotificationMailer.with(notification_id: 0, business_id: 0).notice.tap { def _1.deliver_later = nil } })
    assert_equal [ @owner.email, @admin.email ].sort, mails.sort

    notification = as_business(@business) { Notification.find_by!(user: @owner) }
    mail = NotificationMailer.with(notification_id: notification.id, business_id: @business.id).notice
    assert_equal "Maria opened quote Q-0001", mail.subject
    assert_equal [ @owner.email ], mail.to
    assert_match %r{/admin/quotes/abc}, mail.text_part.body.to_s
    assert_match %r{/admin/notifications/settings}, mail.html_part.body.to_s
  end

  test "named and permission audiences can't be mixed up" do
    assert_raises(ArgumentError) { deliver("quote_viewed", to: [ @tech ]) }
  end

  test "a title that's too long is shortened, and a problem with one recipient never raises" do
    deliver("quote_approved", title: "Quote Q-1 marked approved by #{"x" * 300}")
    assert_equal [ 200 ], as_business(@business) { Notification.pluck(:title).map(&:length).uniq }
    assert_nothing_raised { deliver("quote_declined", path: "https://evil.example/") }
    assert_equal 0, as_business(@business) { Notification.where(kind: "quote_declined").count }
  end

  test "nothing is delivered for a change that's rolled back" do
    Business.transaction do
      deliver("quote_approved")
      raise ActiveRecord::Rollback
    end
    assert_equal 0, as_business(@business) { Notification.count }
  end

  test "unknown kinds raise; paths outside the staff app are refused" do
    assert_raises(NotificationType::UnknownKind) { deliver("nope") }
    [ "https://evil.example/", "/admin/x\nLocation: https://evil.example", "/administrator" ].each { deliver(path: _1) }
    assert_equal 0, as_business(@business) { Notification.count }, "refused (and reported), never raised"
    assert_not as_business(@business) { Notification.new(path: "//evil.example").tap(&:validate).errors[:path].empty? }
  end

  test "members of two businesses see each business's notifications there" do
    deliver("quote_approved")
    assert_equal 1, as_business(@business) { Notification.for_user(@owner).count }
    assert_equal 0, as_business(businesses(:two)) { Notification.for_user(@owner).count }
  end

  test "old notifications are pruned in every business" do
    deliver("quote_approved")
    as_business(@business) { Notification.update_all(created_at: 91.days.ago) }
    deliver("quote_declined")
    PruneNotificationsJob.perform_now
    assert_equal [ "quote_declined" ], as_business(@business) { Notification.distinct.pluck(:kind) }
  end
end
