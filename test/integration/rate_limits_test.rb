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
      get client_link_path(link.token)
      assert_response :too_many_requests
      assert_equal "60", response.headers["Retry-After"]
      assert_select "h1", /a lot of requests/
      assert_select "a[href=?]", client_link_path(link.token), "Try again"

      get invitation_path("x" * 32)
      assert_response :too_many_requests, "counted before the token is looked up"
    end
  end

  test "rate limits that raise get the static 429 page" do
    page = Rails.public_path.join("429.html").read
    assert_match "a lot of requests", page
    assert_no_match %r{<script|https?://}, page
  end
end
