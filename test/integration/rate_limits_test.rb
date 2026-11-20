require "test_helper"

# PLT-13: what each rate-limited public endpoint does once over its limit. The test cache is a
# null store, so "over the limit" is simulated by the store's counter.
class RateLimitsTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  def over_the_limit
    store = ActionController::Base.cache_store
    store.define_singleton_method(:increment) { |*, **| 10_000 }
    yield
  ensure
    store.singleton_class.remove_method(:increment)
  end

  test "sign-in and password reset say to wait, on their own page" do
    over_the_limit do
      post user_session_path, params: { user: { email: users(:one).email, password: "password123" } }
      assert_redirected_to new_user_session_path
      assert_match "Too many sign-in attempts", flash[:alert]
      post user_password_path, params: { user: { email: users(:one).email } }
      assert_redirected_to new_user_password_path
      assert_match "Too many reset requests", flash[:alert]
    end
  end

  test "client links and invitations get the friendly page, with Retry-After" do
    create_test_document_table
    business = businesses(:one)
    link = as_business(business) { ClientLink.issue!(create_test_document(business), actions: %w[approve]) }
    over_the_limit do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      Rails.logger.broadcast_to(logger)
      get client_link_path(link.token)
      Rails.logger.stop_broadcasting_to(logger)
      assert_match %r{\[abuse\] rate limited .*"path":"/c/\[FILTERED\]"}, io.string, "PLT-10: the abuse line keeps the IP, not the token"
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_select "h1", /a lot of requests/
      assert_select "a[href=?]", client_link_path(link.token), "Try again"

      assert_equal "same-origin", response.headers["Referrer-Policy"], "client-page headers on the slow-down page too"
      assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]

      get invitation_path("x" * 32)
      assert_response :too_many_requests, "counted before the token is looked up"
      assert_equal "600", response.headers["Retry-After"]
      assert_select "p", /Wait 10 minutes/
    end
  end

  test "rate limits that raise get the static 429 page" do
    page = Rails.public_path.join("429.html").read
    assert_match "a lot of requests", page
    assert_no_match %r{<script|https?://}, page
  end
end
