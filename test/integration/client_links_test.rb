require "test_helper"

class ClientLinksTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  setup do
    create_test_document_table
    @business = businesses(:one)
    @business.update!(phone: "(555) 010-4477", brand_color: "#9a3412")
    @document = create_test_document(@business)
    @link = as_business(@business) { ClientLink.issue!(@document, actions: %w[approve]) }
  end

  test "a client opens the document with no sign-in, branded and not indexable" do
    get client_link_path(@link.token)
    assert_response :success
    assert_select "#document-title", "Spring cleanup"
    assert_select "body.client[style*='#9a3412']"
    assert_select ".side, .topbar", count: 0
    assert_select "meta[name=robots][content=noindex]"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal 1, @link.reload.views_count
    assert_equal "view", as_business(@business) { @link.events.first.kind }
  end

  test "unknown tokens get a 404 page without business details" do
    get client_link_path("x" * ClientLink::TOKEN_LENGTH)
    assert_response :not_found
    assert_select "h1", /couldn't find/
  end

  test "revoked and expired links explain themselves and offer a fresh link" do
    @link.revoke!
    get client_link_path(@link.token)
    assert_response :gone
    assert_select "h1", /no longer active/
    assert_select "a[href='tel:(555) 010-4477']"
    assert_equal 0, @link.reload.views_count

    post request_fresh_client_link_path(@link.token)
    assert_select "h1", /Request sent/
    assert @link.reload.fresh_link_requested_at

    other = as_business(@business) { ClientLink.issue!(@document, expires_at: 1.day.from_now) }
    travel 2.days do
      get client_link_path(other.token)
      assert_select "h1", /expired/
    end
  end

  test "suspended businesses show a neutral page" do
    @business.update!(active: false)
    get client_link_path(@link.token)
    assert_response :gone
    assert_select "h1", /isn't available/
    assert_select "form[action='#{request_fresh_client_link_path(@link.token)}']", count: 0
  end

  test "a link opens exactly its own document" do
    other_doc = create_test_document(@business, title: "Other job")
    get client_link_path(@link.token)
    assert_select "#document-title", "Spring cleanup"
    assert_no_match "Other job", response.body
    assert other_doc
  end

  test "staff preview renders the client page without counting a view" do
    sign_in users(:one)
    get preview_admin_client_link_path(@link)
    assert_response :success
    assert_select ".banner", /Preview/
    assert_select "#document-title", "Spring cleanup"
    assert_equal 0, @link.reload.views_count
  end

  test "staff can revoke and re-issue" do
    sign_in users(:one)
    patch revoke_admin_client_link_path(@link)
    assert @link.reload.revoked_at
    assert_equal users(:one), @link.revoked_by

    post reissue_admin_client_link_path(@link)
    fresh = Tenancy.across_businesses(reason: "test") { ClientLink.order(:id).last }
    assert_not_equal @link, fresh
    get client_link_path(fresh.token)
    assert_response :success
  end

  test "staff in another business can't touch the link" do
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get preview_admin_client_link_path(@link) }
    assert_not_found_across_businesses { patch revoke_admin_client_link_path(@link) }
    assert_nil @link.reload.revoked_at
  end

  test "technicians can't preview, revoke or re-issue links" do
    tech = User.create!(email: "tech-#{SecureRandom.hex(3)}@example.com", password: "password123", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    sign_in tech
    post switch_admin_business_path, params: { business: @business.uid }
    get preview_admin_client_link_path(@link)
    assert_response :forbidden
    patch revoke_admin_client_link_path(@link)
    assert_response :forbidden
    assert_nil @link.reload.revoked_at
  end

  test "unknown links still get the security headers" do
    get client_link_path("x" * ClientLink::TOKEN_LENGTH)
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
  end

  test "tokens are kept out of request logs" do
    io = StringIO.new
    previous, Rails.logger = Rails.logger, ActiveSupport::Logger.new(io)
    get client_link_path(@link.token)
    assert_match %r{Started GET "/c/\[FILTERED\]"}, io.string
    assert_no_match @link.token, io.string
  ensure
    Rails.logger = previous
  end

  test "deleting a business deletes its links" do
    @link.record_view!
    assert_difference -> { Tenancy.across_businesses(reason: "test") { ClientLink.count } }, -1 do
      Business.find(@business.id).destroy!
    end
  end
end
