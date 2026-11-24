require "test_helper"

# PLT-21: notifications show unread at a glance, and banners keep one live-region rule. The
# sweep (design_system_test.rb) checks the banners it renders; this scans the staff views for
# the states it doesn't reach (form errors, warnings that come back from an action).
class Admin::FeedbackPatternsTest < ActionDispatch::IntegrationTest
  STAFF_VIEWS = Rails.root.glob("app/views/{admin,layouts/app}/**/*.erb")

  test "only an error banner is role=alert, and no banner is a live region of its own" do
    problems = STAFF_VIEWS.flat_map do |file|
      file.read.scan(/<(?:div|section)[^>]*class="banner [^"]*"[^>]*>/).filter_map do |tag|
        where = "#{file.relative_path_from(Rails.root)}: #{tag}"
        next "#{where} is role=alert but not banner-danger" if tag.include?('role="alert"') && !tag.include?("banner-danger")

        "#{where} is a live region; use data-controller=announce" if tag.match?(/role="(status|log)"/)
      end
    end
    assert_empty problems, problems.join("\n")
  end

  test "Notifications: unread is a bold title with a dot and the word for screen readers; read is muted" do
    business = businesses(:one)
    owner = users(:one)
    as_business(business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      NotificationType.deliver("new_request", business:, subject: client, title: "New request from Maria", path: "/admin")
      NotificationType.deliver("new_request", business:, subject: client, title: "Old request from Maria", path: "/admin")
      Notification.find_by!(title: "Old request from Maria").update!(read_at: Time.current)
    end
    sign_in owner
    post switch_admin_business_path, params: { business: business.uid }

    get admin_notifications_path
    assert_select "#notifications li span.font-semibold.text-ink", /New request from Maria/ do
      assert_select ".unread-dot[aria-hidden=true]"
      assert_select ".sr-only", "Unread:"
    end
    assert_select "#notifications li span.text-muted", /Old request from Maria/ do
      assert_select ".unread-dot, .sr-only", 0
    end
    assert_select "#notifications .badge", 0
  end
end
