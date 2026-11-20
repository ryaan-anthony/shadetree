require "test_helper"

# OPS-05: the Email Worker's signed post is the only way email gets in; anything unsigned, stale,
# tampered with or oversized is refused, and nothing about the sender reaches the log.
class Inbound::SupportEmailsTest < ActionDispatch::IntegrationTest
  include InboundEmailHelpers

  def deliver(body, headers = inbound_headers(body)) = post(inbound_support_email_path, params: body, headers:)

  test "a correctly signed email is stored once, with the envelope and Cloudflare's result, and routed" do
    with_inbound_email do
      body = raw_email
      assert_difference -> { ActionMailbox::InboundEmail.count } do
        assert_enqueued_with(job: ActionMailbox::RoutingJob) { deliver(body) }
      end
      assert_response :no_content
      inbound = ActionMailbox::InboundEmail.last
      assert_equal [ "bounce@example.com", "support@getshadetree.com", CLOUDFLARE_PASS ], [ inbound.envelope_from, inbound.envelope_to, inbound.auth_results ]
      assert_equal body, inbound.source

      assert_no_difference(-> { ActionMailbox::InboundEmail.count }, "a retry of the same message") { deliver(body) }
      assert_response :no_content
    end
  end

  test "bad, stale, future or missing signatures and tampered envelopes are refused" do
    with_inbound_email do
      body = raw_email
      good = inbound_headers(body)
      tampered = inbound_headers(body, to: "support+other@getshadetree.com").merge("X-Shadetree-Signature" => good["X-Shadetree-Signature"])
      [ inbound_headers(body, secret: "another-secret-0123456789abcdefghij"), inbound_headers(body, at: 6.minutes.ago),
        inbound_headers(body, at: 6.minutes.from_now), good.except("X-Shadetree-Signature"), tampered ].each do |headers|
        assert_no_difference(-> { ActionMailbox::InboundEmail.count }) { deliver(body, headers) }
        assert_response :unauthorized
      end
      assert_no_difference(-> { ActionMailbox::InboundEmail.count }, "a different body under the same signature") { deliver("#{body}x", good) }
      assert_response :unauthorized
    end
  end

  test "over 25 MiB is refused before it's stored, and so is mail for anyone but support" do
    with_inbound_email do
      body = "x" * (InboundEmailIngress::MAX_BYTES + 1)
      assert_no_difference(-> { ActionMailbox::InboundEmail.count }) { deliver(body, inbound_headers("")) }
      assert_response 413

      other = raw_email(to: "someone@getshadetree.com")
      assert_no_difference(-> { ActionMailbox::InboundEmail.count }) { deliver(other, inbound_headers(other, to: "someone@getshadetree.com")) }
      assert_response :unprocessable_content
    end
  end

  test "without a secret the ingress doesn't exist, and Action Mailbox's own ingresses stay off" do
    with_inbound_email(secret: nil) do
      body = raw_email
      deliver(body)
      assert_response :not_found
    end
    with_inbound_email(secret: "too-short") { deliver(raw_email) }
    assert_response :not_found
    post "/rails/action_mailbox/relay/inbound_emails", params: raw_email, headers: { "Content-Type" => "message/rfc822" }
    assert_response :not_found
  end

  test "posts are rate limited per IP address" do
    store = Inbound::SupportEmailsController.cache_store
    store.define_singleton_method(:increment) { |*, **| 10_000 } # the test cache is a null store
    with_inbound_email do
      post inbound_support_email_path, params: "x", headers: { "Content-Type" => "message/rfc822" }
      assert_response :too_many_requests
    end
  ensure
    store.singleton_class.remove_method(:increment)
  end

  test "the log says what happened, never who sent it" do
    with_inbound_email do
      body = raw_email(from: "distinctive.sender@example.com", subject: "Private matter")
      log = capture_json_log do
        deliver(body, inbound_headers(body, from: "distinctive.sender@example.com"))
        deliver(body, inbound_headers(body, from: "distinctive.sender@example.com", at: 1.hour.ago))
        perform_enqueued_jobs
      end
      assert_includes log, "inbound_email.accepted"
      assert_includes log, "bad_signature"
      assert_no_match(/distinctive|Private matter|@example\.com/, log)
    end
  end
end
