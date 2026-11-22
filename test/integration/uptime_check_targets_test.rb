require "test_helper"

# PLT-10: uptime targets (docs/runbooks/operations.md, Monitoring). Sentry's uptime monitor polls
# production /up today; the client-link target is ready for a later monitor. Each answers without
# side effects. The client-link check uses a well-formed token that is never
# issued, so it runs the client page's whole stack (routing, rate limit, link lookup, the client
# layout) without a real link, whose view would be recorded and could notify a business.
class UptimeCheckTargetsTest < ActionDispatch::IntegrationTest
  SYNTHETIC_TOKEN = "1" * ClientLink::TOKEN_LENGTH

  test "/up answers 200" do
    get "/up"
    assert_response :success
  end

  test "the synthetic client link answers 404 with the client page, and changes nothing" do
    assert_nil ClientLink.find_by_token(SYNTHETIC_TOKEN)
    counts = -> { Tenancy.across_businesses(reason: "test: nothing recorded anywhere") { [ ClientLink.sum(:views_count), ClientLinkEvent.count ] } }
    assert_no_changes counts do
      get "/c/#{SYNTHETIC_TOKEN}"
    end
    assert_response :not_found
    assert_select "h1", "We couldn't find that page"
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end
end
