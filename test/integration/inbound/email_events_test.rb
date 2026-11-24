require "test_helper"

# NTF-05 (ADR 0028): bounce and complaint reports come in signed and fresh, in our JSON or as a
# standard DSN; they're matched in the request and only an event about one of our emails, to its
# own recipient, within 14 days, is stored, once, without the address.
class Inbound::EmailEventsTest < ActionDispatch::IntegrationTest
  include EmailEventHelpers
  include InboundEmailHelpers # capture_json_log

  setup { @email = sent_email(businesses(:one), cc: "Office@Example.com, ana@example.com") }

  def post_event(body, headers = event_headers(body)) = post(inbound_email_events_path, params: body, headers:)
  def stored = Tenancy.across_businesses(reason: "test") { EmailEvent.order(:id).to_a }
  def tally = EmailEventTally.recent

  test "a signed JSON bounce is stored once, with what the app acts on and nothing about the address" do
    with_email_events do
      body = event_json(@email, id: "evt-1")
      assert_difference(-> { stored.size }) { post_event(body) }
      assert_response :no_content
      event = stored.last
      assert_equal [ @email.id, businesses(:one).id, "bounce", "5.1.1", "550", "mailbox", "to", nil ],
                   [ event.email_message_id, event.business_id, event.event_type, event.status_code, event.reply_code, event.reason, event.recipient_role, event.cc_position ]
      assert_no_match(/maria|example\.com/, event.attributes.values.join(" "))

      assert_no_difference(-> { stored.size }, "a repeat of the same event id does nothing") { post_event(event_json(@email, id: "evt-1", status: "5.7.1")) }
      assert_response :no_content
      assert_equal({ received: 2, matched: 2, dropped: 0 }, tally)
    end
  end

  test "bad, stale, future or missing signatures are refused, and so is a changed body" do
    with_email_events do
      body = event_json(@email)
      [ event_headers(body, secret: "another-secret-0123456789abcdefghijkl"), event_headers(body, at: 6.minutes.ago),
        event_headers(body, at: 6.minutes.from_now), event_headers(body).except("X-Shadetree-Signature") ].each do |headers|
        post_event(body, headers)
        assert_response :unauthorized
      end
      post_event("#{body} ", event_headers(body))
      assert_response :unauthorized
      assert_empty stored
      assert_equal({ received: 0, matched: 0, dropped: 0 }, tally, "refused posts aren't events")
    end
  end

  test "over 256 KB is refused before it's read, and without a secret the endpoint isn't there" do
    with_email_events do
      post_event("x" * (EmailEventIngress::MAX_BYTES + 1), event_headers(""))
      assert_response 413
    end
    with_email_events(secret: nil) { post_event(event_json(@email)) }
    assert_response :not_found
    with_email_events(secret: "too-short") { post_event(event_json(@email)) }
    assert_response :not_found
  end

  test "failed attempts are rate limited per IP; signed posts never are" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    with_email_events do
      35.times { post_event(event_json(@email)) }
      assert_response :no_content
      body = event_json(@email)
      Inbound::EmailEventsController::FAILURES_PER_MINUTE.times { post_event(body, event_headers(body, at: 1.hour.ago)) }
      post_event(event_json(@email))
      assert_response :too_many_requests
    end
  ensure
    Rails.cache = cache
  end

  test "our JSON is strict: unknown keys, another version, a missing status or a bad code refuse the post" do
    with_email_events do
      [ event_json(@email, extra: "x"), event_json(@email, version: 2), event_json(@email, status: nil), event_json(@email, status: "5.1"),
        event_json(@email, reply_code: "55"), event_json(@email, type: "opened"), event_json(@email, message_id: nil), event_json(@email, occurred_at: "yesterday"),
        "[1]", "not json" ].each do |body|
        post_event(body)
        assert_response :unprocessable_content, body
      end
      assert_empty stored
    end
  end

  test "a DSN matches by the returned Message-ID or reference header, one event per recipient" do
    with_email_events do
      body = dsn_report(@email, recipients: [ [ "maria@example.com", "failed", "5.1.1", "smtp; 550 5.1.1 no such user" ],
                                              [ "ana@example.com", "failed", "5.2.2", "smtp; 552 5.2.2 mailbox full" ],
                                              [ "office@example.com", "delayed", "4.4.1", "smtp; 421 try later" ] ])
      post_event(body, event_headers(body, type: "message/rfc822"))
      assert_response :no_content
      assert_equal [ [ "to", nil, "mailbox", "550", "5.1.1" ], [ "cc", 1, "refused", "552", "5.2.2" ] ],
                   stored.map { [ _1.recipient_role, _1.cc_position, _1.reason, _1.reply_code, _1.status_code ] }
      assert_equal({ received: 3, matched: 2, dropped: 1 }, tally)

      post_event(body, event_headers(body, type: "message/rfc822"))
      assert_equal 2, stored.size, "the same report again is a repeat"

      by_reference = dsn_report(@email, message_id: "rewritten-by-the-relay@relay.example")
      assert_difference(-> { stored.size }) { post_event(by_reference, event_headers(by_reference, type: "multipart/report")) }
      post_event("From: a@example.com\r\n\r\nhello", event_headers("From: a@example.com\r\n\r\nhello", type: "message/rfc822"))
      assert_response :unprocessable_content
    end
  end

  test "unmatched events, other recipients, delays, temporary statuses and events after 14 days are counted, not stored" do
    late = sent_email(businesses(:one), sent_at: 15.days.ago)
    with_email_events do
      [ event_json(@email, message_id: "<unknown@getshadetree.com>"), event_json(@email, message_id: nil, reference: "nope"),
        event_json(@email, recipient: "someone-else@example.com"), event_json(@email, type: "delay", status: "4.4.1"),
        event_json(@email, status: "4.2.2"), event_json(late), event_json(@email, type: "bounce", status: "2.0.0") ].each { post_event(_1) }
      assert_response :no_content
      assert_empty stored
      assert_equal({ received: 7, matched: 0, dropped: 7 }, tally)

      post_event(event_json(late, occurred_at: (late.sent_at + 13.days).iso8601))
      assert_equal 1, stored.size, "the 14 days run from the send, not from when the report arrives"
    end
  end

  test "a complaint without a recipient is about the To; a CC is matched case-blind; each email stays in its own business" do
    other = sent_email(businesses(:two), to: "maria@example.com")
    with_email_events do
      post_event(event_json(@email, type: "complaint", recipient: nil, status: nil, reply_code: nil))
      post_event(event_json(@email, recipient: "OFFICE@example.com"))
      post_event(event_json(other))
      assert_equal [ [ "complaint", "to", nil, businesses(:one).id ], [ "bounce", "cc", 0, businesses(:one).id ], [ "bounce", "to", nil, businesses(:two).id ] ],
                   stored.map { [ _1.event_type, _1.recipient_role, _1.cc_position, _1.business_id ] }
    end
    assert_equal 2, as_business(businesses(:one)) { EmailEvent.count }
    assert_equal [ other.id ], as_business(businesses(:two)) { EmailEvent.pluck(:email_message_id) }
  end

  test "the log says what happened, never who" do
    with_email_events do
      log = capture_json_log { post_event(event_json(@email)) }
      line = log.lines.map { JSON.parse(_1) }.find { _1["event"] == "email_events.received" }
      assert_equal({ "stored" => 1 }, line["outcomes"])
      assert_no_match(/maria|example\.com|#{Regexp.escape(@email.provider_message_id)}/, log)
    end
  end
end
