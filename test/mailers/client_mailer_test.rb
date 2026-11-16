require "test_helper"

# NTF-01: branded client email, sender and reply-to, tracking and suppression.
class ClientMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(email: "office@oakline.example", phone: "555-380-0000", address_line1: "1 Main St", city: "Asheville", brand_color: "#9a3412")
  end

  def send_test(to = "dana@example.com")
    ClientMailer.send_later(:test_message, business: @business, to:, kind: "test_message", related: @business, recipient_name: "Dana")
  end

  test "sends as the business via Shadetree, with replies to the business" do
    message = perform_enqueued_jobs { send_test }
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "dana@example.com" ], mail.to
    assert_equal "#{@business.name} via Shadetree", mail[:from].display_names.first
    assert_equal [ "office@oakline.example" ], mail.reply_to
    assert_equal message.uid, mail["X-Shadetree-Email"].value
    assert_match(/\A[0-9a-f-]{36}@getshadetree\.com\z/, mail.message_id, "a Message-ID on the sending domain")
    assert_equal "Test email from #{@business.name}", mail.subject

    message = as_business(@business) { message.reload }
    assert_equal "sent", message.status
    assert_equal "Test email from #{@business.name}", message.subject
    assert_equal mail.message_id, message.provider_message_id
    assert message.sent_at
  end

  test "the branded layout has the logo or wordmark, brand color, contact footer and a text part" do
    perform_enqueued_jobs { send_test }
    mail = ActionMailer::Base.deliveries.last
    html = mail.html_part.body.to_s
    text = mail.text_part.body.to_s
    assert_includes html, "border-top:4px solid #9a3412"
    assert_includes html, ">TB</td>"
    assert_includes html, "1 Main St, Asheville"
    assert_includes html, %(content="light only")
    assert_includes text, "Reply to this email to reach #{@business.name}"
    assert_includes text, "555-380-0000"
    assert_not_includes text, "<"

    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    perform_enqueued_jobs { send_test }
    assert_match %r{<img src="http://example\.com/rails/active_storage/representations/redirect/[^"]+/logo\.png"}, ActionMailer::Base.deliveries.last.html_part.body.to_s
  end

  test "suppressed addresses aren't emailed" do
    as_business(@business) { EmailSuppression.suppress!("dana@example.com", reason: "hard_bounce") }
    message = perform_enqueued_jobs { send_test("Dana@Example.com") }
    assert_empty ActionMailer::Base.deliveries
    assert_equal "suppressed", as_business(@business) { message.reload.status }
  end

  # A delivery method that raises whatever the test sets.
  class FailingDelivery
    cattr_accessor :error
    def initialize(*) = nil
    def deliver!(*) = raise(error)
  end
  ActionMailer::Base.add_delivery_method :failing, FailingDelivery

  def with_failing_delivery(error)
    FailingDelivery.error = error
    previous, ClientMailer.delivery_method = ClientMailer.delivery_method, :failing
    yield
  ensure
    ClientMailer.delivery_method = previous
  end

  test "failures are retried, then shown as failed on the record" do
    message = send_test
    with_failing_delivery(Net::ReadTimeout.new("provider timed out")) do
      ClientMailDeliveryJob::ATTEMPTS.times { perform_enqueued_jobs(at: 1.year.from_now) }
    end
    message = as_business(@business) { message.reload }
    assert_equal "failed", message.status
    assert_equal "The mail server couldn't be reached (ReadTimeout).", message.error
    assert message.problem?
    assert_no_enqueued_jobs
  end

  class PlatformMailer < ApplicationMailer
    def hello = mail(to: "owner@example.com", subject: "Hi", body: "Hi")
  end

  test "platform mail gets a Message-ID on the sending domain too" do
    assert_match(/\A[0-9a-f-]{36}@getshadetree\.com\z/, PlatformMailer.hello.deliver_now.message_id)
  end

  def smtp_error(klass, reply) = klass.new(Net::SMTP::Response.parse(reply))

  test "an address the mail server refuses fails at once and is flagged, without the reply in the record" do
    message = send_test
    with_failing_delivery(smtp_error(Net::SMTPFatalError, "550 5.1.1 <dana@example.com>: Recipient address rejected")) { perform_enqueued_jobs }
    assert_no_enqueued_jobs
    message = as_business(@business) { message.reload }
    assert_equal [ "bounced", "The mail server refused this address (550 5.1.1)." ], [ message.status, message.error ]
    assert as_business(@business) { EmailSuppression.suppressed?("dana@example.com") }
  end

  test "a permanent refusal that isn't about the address fails without flagging it" do
    message = send_test
    with_failing_delivery(smtp_error(Net::SMTPFatalError, "554 5.7.1 Message rejected as spam")) { perform_enqueued_jobs }
    assert_no_enqueued_jobs
    assert_equal [ "failed", "The mail server refused the message (554 5.7.1)." ], as_business(@business) { message.reload.then { [ _1.status, _1.error ] } }
    assert_not as_business(@business) { EmailSuppression.suppressed?("dana@example.com") }
  end

  test "bad credentials fail at once" do
    message = send_test
    with_failing_delivery(smtp_error(Net::SMTPAuthenticationError, "535 5.7.8 Authentication failed")) { perform_enqueued_jobs }
    assert_no_enqueued_jobs
    assert_equal "The mail server rejected our credentials.", as_business(@business) { message.reload.error }
  end

  test "a busy server or a timeout is retried" do
    send_test
    with_failing_delivery(smtp_error(Net::SMTPServerBusy, "421 4.7.0 Try again later")) { perform_enqueued_jobs }
    assert_enqueued_jobs 1, only: ClientMailDeliveryJob
  end

  test "without a provider, nothing is sent and the record says so" do
    message = send_test
    ActionMailer::Base.perform_deliveries = false
    perform_enqueued_jobs
    assert_empty ActionMailer::Base.deliveries
    assert_equal [ "failed", "Email sending isn't set up yet." ], as_business(@business) { message.reload.then { [ _1.status, _1.error ] } }
  ensure
    ActionMailer::Base.perform_deliveries = true
  end

  test "every recorded email type is in the catalog" do
    assert_raises(ArgumentError) { ClientMailer.send_later(:test_message, business: @business, to: "x@example.com", kind: "made_up") }
    assert_equal EmailCatalog.kinds.uniq, EmailCatalog.kinds
  end
end
