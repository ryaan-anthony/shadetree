require "test_helper"

# OPS-05: email to support threads into tickets only when the sender is proven: a reply through
# the member's signed reply address, from that member, with Cloudflare's SPF/DKIM/DMARC pass; a
# new ticket with DMARC pass from an active member. Everything else is dropped quietly.
class SupportMailTest < ActiveSupport::TestCase
  include PermissionHelpers
  include InboundEmailHelpers

  setup do
    @business = businesses(:one)
    @ticket = as_business(@business) { SupportTicket.open!(opened_by: users(:one), subject: "Logo", category: "bug", body: "Blurry") }
    as_business(@business) { @ticket.change_status!("resolved") }
    @reply_to = SupportMail.reply_address(@ticket, users(:one))
  end

  def email(from: "user1@example.com", subject: "Re: Logo", body: "Still blurry.\n\nOn Tue, Shadetree Support wrote:\n> Try a PNG", **headers)
    Mail.new(raw_email(from:, subject:, body:, **headers))
  end

  def receive(mail = email, to: @reply_to, from: "bounce@example.com", auth: CLOUDFLARE_PASS)
    SupportMail.receive(mail, envelope_to: to, envelope_from: from, auth_results: auth)
  end

  def message_count = as_business(@business) { @ticket.messages.count }

  test "a reply to the signed address adds to the thread and reopens the ticket" do
    assert_match(/\Asupport\+[0-9a-z]+-[0-9a-z]+-[0-9a-f]{20}@getshadetree\.com\z/, @reply_to)
    assert_operator @reply_to.split("@").first.length, :<=, 64
    result = receive
    assert_equal [ :replied, @ticket ], [ result.outcome, result.ticket ]
    message = as_business(@business) { @ticket.messages.last }
    assert_equal [ "Still blurry.", "email", users(:one) ], [ message.body, message.source, message.author ]
    assert_equal "open", @ticket.reload.status
    assert_equal :replied, receive(email(body: "More"), to: @reply_to.upcase).outcome, "addresses are case-insensitive"
  end

  test "a forged From with a valid token, or a token that's been tampered with, is refused" do
    cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    assert_equal :forged_sender, receive(email(from: "user2@example.com", body: "Secret forged text")).outcome
    assert_equal :forged_sender, receive(email(from: "someone@evil.example")).outcome
    notes = as_business(@business) { @ticket.messages.where(internal: true).to_a }
    assert_equal [ SupportTicket::UNVERIFIED_EMAIL_NOTE ], notes.map(&:body), "one operator-only note an hour, with nothing from the email"
    assert_equal "resolved", @ticket.reload.status
    Rails.cache = cache
    tampered = @reply_to.sub(/-([0-9a-z]+)-/) { "-#{users(:two).id.to_s(36)}-" }
    assert_equal :bad_token, receive(email(from: "user2@example.com"), to: tampered).outcome
    assert_equal :bad_token, receive(to: @reply_to.sub(/([0-9a-f])@/) { "#{::Regexp.last_match(1) == "0" ? "1" : "0"}@" }).outcome
    assert_equal :bad_token, receive(to: "support+nonsense@getshadetree.com").outcome
    assert_equal 2, message_count, "the opening message and the note"
    assert_equal [ "Blurry" ], as_business(@business) { @ticket.visible_messages.map(&:body) }
  end

  test "missing, failed, unaligned or someone else's authentication results are refused" do
    [ "", "mx.cloudflare.net; spf=fail smtp.mailfrom=x@example.com; dkim=none; dmarc=fail header.from=example.com",
      "mx.cloudflare.net; spf=pass smtp.mailfrom=x@evil.example; dkim=pass header.d=evil.example; dmarc=fail header.from=example.com",
      'mx.cloudflare.net; dkim=fail header.d=example.com; dmarc=fail header.from=example.com; spf=pass smtp.mailfrom="x;dmarc=pass header.from=example.com"@evil.example',
      "mx.cloudflare.net; dkim=none; dmarc=none, x y; dkim=pass header.d=example.com",
      "mx.evil.example; spf=pass smtp.mailfrom=x@example.com; dkim=pass header.d=example.com; dmarc=pass header.from=example.com" ].each do |auth|
      assert_equal :unauthenticated, receive(auth:).outcome, auth
    end
    assert_equal :replied, receive(auth: "mx.cloudflare.net; dkim=pass header.d=example.com; dmarc=none header.from=example.com").outcome,
                 "an aligned DKIM pass is enough for a signed reply"
  end

  test "a subject or Message-ID naming the ticket opens nothing on its own" do
    mail = email(subject: "Re: Logo [##{@ticket.uid}]", in_reply_to: "<ticket-#{@ticket.uid}-1-abcd@getshadetree.com>")
    result = receive(mail, to: "support@getshadetree.com")
    assert_equal :opened, result.outcome
    assert_not_equal @ticket, result.ticket
    assert_equal 1, message_count
    assert_equal :unauthenticated, receive(mail, to: "support@getshadetree.com", auth: "mx.cloudflare.net; spf=pass smtp.mailfrom=x@example.com").outcome
  end

  test "a reply only reaches a ticket its user may still see (OPS-05 visibility, membership)" do
    tech = member_with_role("technician")
    assert_equal :forged_sender, receive(email(from: tech.email)).outcome
    assert_equal :not_member, receive(email(from: tech.email), to: SupportMail.reply_address(@ticket, tech)).outcome, "not their ticket"
    users(:one).business_users.find_by!(business: @business).update_columns(active: false)
    assert_equal :not_member, receive.outcome
    assert_equal [ "Blurry" ], as_business(@business) { @ticket.visible_messages.map(&:body) }
  end

  test "a new ticket needs DMARC pass and an active member, in the business they last used" do
    mail = email(subject: "Fwd: Can't log in on my phone", body: "It spins forever.")
    mail.add_file(filename: "shot.png", content: file_fixture("logo.png").binread)
    users(:one).update_columns(last_business_id: businesses(:two).id)
    dkim_only = "mx.cloudflare.net; dkim=pass header.d=example.com; dmarc=none header.from=example.com"
    assert_equal :unauthenticated, receive(mail, to: "support@getshadetree.com", auth: dkim_only).outcome
    result = receive(mail, to: "support@getshadetree.com")
    assert_equal :opened, result.outcome
    assert_equal [ businesses(:two), "Can't log in on my phone", "Email" ], [ result.ticket.business, result.ticket.subject, result.ticket.browser ]
    assert as_business(businesses(:two)) { result.ticket.messages.first.files.attached? }

    joined = "mx.cloudflare.net; dkim=none; spf=none, x y; dkim=pass header.d=example.com; dmarc=pass header.from=example.com"
    assert_equal :unauthenticated, receive(email, to: "support@getshadetree.com", auth: joined).outcome, "a sender's header joined on"
    assert_equal :not_member, receive(email(from: "stranger@example.com"), to: "support@getshadetree.com").outcome
    assert_equal :empty, receive(email(body: "> only quoted"), to: "support@getshadetree.com").outcome
  end

  test "each sender is rate limited, counting only mail that proved its sender" do
    with_counting_rate_limits do
      5.times { receive(email(from: "user2@example.com")) } # forged: doesn't use up user one's allowance
      outcomes = 11.times.map { receive(email(body: "Again #{_1}")).outcome }
      assert_equal [ :replied ] * 10 + [ :rate_limited ], outcomes
    end
  end

  test "unusable attachments are skipped, not the reply: inline, SVG, GIF and broken files" do
    mail = email(body: "Screenshot attached")
    mail.add_file(filename: "shot.png", content: file_fixture("logo.png").binread)
    mail.add_file(filename: "broken.png", content: "not really a png")
    mail.add_file(filename: "logo.svg", content: "<svg xmlns='http://www.w3.org/2000/svg'/>")
    mail.add_file(filename: "anim.gif", content: "GIF89a")
    mail.attachments.inline["sig.png"] = file_fixture("logo.png").binread
    assert_equal :replied, receive(mail).outcome
    files = as_business(@business) { @ticket.messages.last.files }
    assert_equal [ "image/png" ], files.map(&:content_type)
  end

  test "HTML-only replies come through as text, entities decoded" do
    mail = Mail.new do
      from "user1@example.com"
      subject "Re: Logo"
      html_part { content_type "text/html; charset=UTF-8"; body "<p>Tom &amp; Jerry&#39;s &lt;invoice&gt;</p>" }
    end
    assert_equal :replied, receive(mail).outcome
    assert_equal "Tom & Jerry's <invoice>", as_business(@business) { @ticket.messages.last.body }
  end

  test "bounces, auto-replies and list mail are ignored" do
    assert_equal :automated, receive(from: "").outcome
    assert_equal :automated, receive(from: "<>").outcome
    assert_equal :automated, receive(email(auto_submitted: "auto-replied")).outcome
    assert_equal :automated, receive(email(precedence: "bulk")).outcome
    assert_equal :automated, receive(email(return_path: "<>")).outcome
    assert_equal :automated, receive(email(from: "MAILER-DAEMON@example.com")).outcome
    assert_equal :automated, receive(email(list_id: "<news.example.com>")).outcome
    assert_equal 1, message_count
    assert_equal :replied, receive(email(auto_submitted: "no")).outcome
  end

  test "support emails carry the signed reply address and say so only once inbound email is on" do
    message = as_business(@business) { @ticket.reply_from_operator!(users(:two), "Try a PNG") }
    build = -> { SupportMailer.with(business_id: @business.id, message_id: message.id, user: users(:one)).reply }
    off = build.call
    assert_equal [ "support@getshadetree.com" ], off.reply_to
    assert_match "Reply in Shadetree.", off.text_part.body.to_s
    with_inbound_email do
      on = build.call
      assert_equal [ @reply_to ], on.reply_to
      assert_match "Reply to this email or in Shadetree.", on.text_part.body.to_s
      assert_match "Reply to this email or in Shadetree.", on.html_part.body.to_s
    end
  end
end
