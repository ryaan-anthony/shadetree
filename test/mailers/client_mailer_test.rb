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
    mail = ActionMailer::Base.deliveries.last
    logo = mail.attachments.find(&:inline?)
    assert logo, "the logo travels inside the email"
    assert_equal "image/png", logo.mime_type
    assert_operator logo.body.decoded.bytesize, :>, 0
    html = mail.html_part.body.to_s
    assert_includes html, %(<img src="cid:#{logo.cid}")
    assert_not_includes html, "active_storage", "no link back to the app"
    assert_not_includes html, ">TB</td>"
  end

  test "a logo that can't be read falls back to the wordmark, and the email still goes" do
    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    @business.logo.blob.service.delete(@business.logo.blob.key)
    assert_error_reported { perform_enqueued_jobs { send_test } }
    mail = ActionMailer::Base.deliveries.last
    assert_nil mail.attachments.find(&:inline?)
    assert_includes mail.html_part.body.to_s, ">TB</td>"
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

  # Delivers through FakeSmtpServer, so net-smtp raises what it really raises at each stage.
  def deliver_over_smtp(**replies)
    FakeSmtpServer.run(**replies) do |settings|
      previous = [ ClientMailer.delivery_method, ClientMailer.smtp_settings ]
      ClientMailer.delivery_method = :smtp
      ClientMailer.smtp_settings = settings
      yield
    ensure
      ClientMailer.delivery_method, ClientMailer.smtp_settings = previous
    end
  end

  def outcome(message) = as_business(@business) { message.reload.then { [ _1.status, _1.error ] } }
  def suppressed? = as_business(@business) { EmailSuppression.suppressed?("dana@example.com") }

  test "a clean SMTP conversation marks the email sent" do
    message = send_test
    deliver_over_smtp { perform_enqueued_jobs }
    assert_equal [ "sent", nil ], outcome(message)
  end

  test "a mailbox the server refuses (550 5.1.1, or 501 5.1.3 syntax) is bounced and flagged, without the reply text" do
    { "550 5.1.1 <dana@example.com>: Recipient address rejected" => "550 5.1.1", "501 5.1.3 Bad recipient address syntax" => "501 5.1.3" }.each do |reply, label|
      message = send_test
      deliver_over_smtp(rcpt: reply) { perform_enqueued_jobs }
      assert_no_enqueued_jobs
      assert_equal [ "bounced", "The mail server refused this address (#{label})." ], outcome(message), reply
      assert suppressed?
      as_business(@business) { EmailSuppression.clear!("dana@example.com") }
    end
  end

  test "refusals that aren't about the mailbox fail without flagging it: sender, policy, content" do
    { { mail: "550 5.7.1 Sender address not verified" } => "550 5.7.1", { mail: "553 5.1.8 Sender domain rejected" } => "553 5.1.8",
      { rcpt: "550 Mailbox unavailable" } => "550", { message: "554 5.7.1 Message rejected as spam" } => "554 5.7.1" }.each do |replies, label|
      message = send_test
      deliver_over_smtp(**replies) { perform_enqueued_jobs }
      assert_no_enqueued_jobs
      assert_equal [ "failed", "The mail server refused the email (#{label})." ], outcome(message), replies.inspect
      assert_not suppressed?
    end
  end

  test "rejected credentials fail at once; a temporary AUTH reply is retried" do
    message = send_test
    deliver_over_smtp(auth: "535 5.7.8 Authentication credentials invalid") { perform_enqueued_jobs }
    assert_equal [ "failed", "The mail server refused the email (credentials rejected, 535 5.7.8)." ], outcome(message)

    send_test
    deliver_over_smtp(auth: "454 4.7.0 Temporary authentication failure") { perform_enqueued_jobs }
    assert_enqueued_jobs 1, only: ClientMailDeliveryJob
  end

  test "temporary replies and connection errors are retried, then failed, without addresses in the logs" do
    message = send_test
    logged = StringIO.new
    previous, ActiveJob::Base.logger = ActiveJob::Base.logger, ActiveSupport::Logger.new(logged)
    deliver_over_smtp(rcpt: "450 4.2.0 <dana@example.com>: Mailbox busy") do
      ClientMailDeliveryJob::ATTEMPTS.times { perform_enqueued_jobs(at: 1.year.from_now) }
    end
    assert_equal [ "failed", "The mail server couldn't take the email (450 4.2.0)." ], outcome(message)
    assert_no_match "dana@example.com", logged.string
    assert_match "Retrying", logged.string
  ensure
    ActiveJob::Base.logger = previous
  end

  test "a server that isn't there is retried" do
    message = send_test
    with_failing_delivery(Errno::ECONNREFUSED.new) { perform_enqueued_jobs }
    assert_enqueued_jobs 1, only: ClientMailDeliveryJob
    assert_equal "queued", as_business(@business) { message.reload.status }
  end

  test "a bug isn't retried as a mail problem: the email is marked failed and the error raised" do
    message = send_test
    with_failing_delivery(NoMethodError.new("undefined method")) do
      assert_raises(NoMethodError) { perform_enqueued_jobs }
    end
    assert_equal [ "failed", "Something went wrong sending this email." ], outcome(message)
  end

  class PlatformMailer < ApplicationMailer
    def hello = mail(to: "owner@example.com", subject: "Hi", body: "Hi")
  end

  test "platform mail gets a Message-ID on the sending domain, and goes out in the background" do
    assert_match(/\A[0-9a-f-]{36}@getshadetree\.com\z/, PlatformMailer.hello.deliver_now.message_id)
    assert_equal PlatformMailDeliveryJob, PlatformMailer.delivery_job
    assert_enqueued_with(job: PlatformMailDeliveryJob) { users(:unconfirmed).send_confirmation_instructions }
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
