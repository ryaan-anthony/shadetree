require "test_helper"
require "rake"

# MKT-02: the contact form keeps messages and emails the team and the sender; PLT-13's guards
# keep bots out; spam is kept for review without emailing anyone.
class ContactFormTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @cache, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
  end

  teardown { Rails.cache = @cache }

  def send_message(at: 1.minute.ago, **fields)
    fields = { name: "Ana Silva", email: "Ana@Example.com", business_name: "Silva Lawns", industry: "landscaping",
               body: "Do you handle recurring mowing visits?" }.merge(fields)
    post contact_path, params: { contact_message: fields, **form_guard_params("contact", at:) }
  end

  test "the form asks for name, email, an optional business and industry, and the message" do
    get contact_path
    assert_response :success
    assert_select "h1", "Get in touch"
    assert_select "input[name='contact_message[name]'][required]"
    assert_select "input[name='contact_message[email]'][type=email][required]"
    assert_select "input[name='contact_message[business_name]']:not([required])"
    assert_select "select[name='contact_message[industry]'] option", minimum: 3
    assert_select "textarea[name='contact_message[body]'][required]"
    assert_select "input[name=website]"
    assert_select "input[name=form_token]"
  end

  test "a message is kept, the team gets it with reply-to set to the sender, and the sender gets a confirmation" do
    perform_enqueued_jobs do
      assert_difference -> { ContactMessage.count } => 1, -> { ActionMailer::Base.deliveries.size } => 2 do
        send_message
      end
    end
    assert_redirected_to contact_sent_path
    follow_redirect!
    assert_select "h1", "Message sent"
    assert_select "[role=status]", /emailed you a confirmation/

    message = ContactMessage.last
    assert_equal [ "Ana Silva", "ana@example.com", "Silva Lawns", "landscaping" ], [ message.name, message.email, message.business_name, message.industry ]
    assert message.notified_at
    assert_not message.spam?

    team, confirmation = ActionMailer::Base.deliveries.last(2).sort_by { _1.to.first == "support@getshadetree.com" ? 0 : 1 }
    assert_equal [ "support@getshadetree.com" ], team.to
    assert_equal [ "ana@example.com" ], team.reply_to
    assert_equal "Contact form: Ana Silva (Silva Lawns)", team.subject
    assert_match "Do you handle recurring mowing visits?", team.text_part.body.to_s
    assert_match "Landscaping", team.text_part.body.to_s
    assert_equal [ "ana@example.com" ], confirmation.to
    assert_no_match(/recurring mowing/, confirmation.text_part.body.to_s, "the confirmation doesn't repeat the message")
  end

  test "missing or bad fields are explained inline, and nothing is kept" do
    assert_no_difference -> { ContactMessage.count } do
      send_message(name: "", email: "not-an-email", body: "", industry: "astrology")
    end
    assert_response :unprocessable_content
    assert_select "#contact_message_name_error", /Enter your name/
    assert_select "#contact_message_email_error", /email doesn't look right/
    assert_select "#contact_message_body_error", /Write your message/
    assert_select "#contact_message_industry_error", /Choose an industry/
    assert_select "input[name='contact_message[email]'][value=?]", "not-an-email"
  end

  test "bots: the hidden field shows the usual page and keeps nothing; a fast or reused form is refused" do
    assert_no_difference -> { ContactMessage.count } do
      post contact_path, params: { contact_message: { name: "Bot", email: "b@example.com", body: "hi" }, **form_guard_params("contact"), website: "x" }
    end
    assert_redirected_to contact_sent_path

    send_message(at: 1.second.ago)
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Check your details/

    params = { contact_message: { name: "Ana", email: "ana@example.com", body: "Hi there" }, **form_guard_params("contact") }
    post contact_path, params: params
    assert_redirected_to contact_sent_path
    post contact_path, params: params
    assert_response :unprocessable_content
  end

  test "too many messages from one network are refused" do
    5.times { send_message }
    send_message
    assert_response :unprocessable_content
    assert_select "[role=alert]", /a lot of messages from your network/
    assert_equal 5, ContactMessage.count
  end

  test "spam is kept for review and nobody is emailed" do
    perform_enqueued_jobs do
      assert_no_emails do
        send_message(body: "Cheap backlinks http://a.example http://b.example http://c.example")
        send_message(name: "Win www.spam.example", body: "Hello")
        send_message(body: "Best casino bonus")
      end
    end
    assert_redirected_to contact_sent_path
    follow_redirect!
    assert_select "[role=status]" do |status|
      assert_no_match(/confirmation/, status.text, "nothing was emailed, so the page doesn't say so")
    end
    assert_equal [ "link in name", "spam words", "too many links" ], ContactMessage.spam.pluck(:spam_reason).sort
  end

  test "one confirmation an hour per address, but the team hears about every message" do
    perform_enqueued_jobs do
      send_message
      send_message(body: "And another question")
    end
    assert_equal 3, ActionMailer::Base.deliveries.size
    assert_equal 1, ActionMailer::Base.deliveries.count { _1.to == [ "ana@example.com" ] }
  end

  test "names can't break the email headers" do
    perform_enqueued_jobs { send_message(name: "Ana\r\nBcc: victim@example.com") }
    team = ActionMailer::Base.deliveries.find { _1.to == [ "support@getshadetree.com" ] }
    assert_empty Array(team.bcc)
    assert_equal "Ana Bcc: victim@example.com", ContactMessage.last.name
  end

  test "messages are pruned after two years (spam after 30 days) and erased on request" do
    old = ContactMessage.create!(name: "Old", email: "old@example.com", body: "x", created_at: 25.months.ago)
    old_spam = ContactMessage.create!(name: "Spam", email: "s@example.com", body: "x", spam_reason: "spam words", created_at: 31.days.ago)
    kept = ContactMessage.create!(name: "Kept", email: "Kept@example.com", body: "x", created_at: 1.year.ago)
    PruneContactMessagesJob.perform_now
    assert_equal [ kept ], ContactMessage.all.to_a
    assert_not ContactMessage.exists?(old.id) || ContactMessage.exists?(old_spam.id)

    Rails.application.load_tasks unless Rake::Task.task_defined?("contact:erase")
    ENV["EMAIL"] = " KEPT@example.com "
    assert_output(/Deleted 1 message/) { Rake::Task["contact:erase"].tap(&:reenable).invoke }
    assert_empty ContactMessage.all
  ensure
    ENV.delete("EMAIL")
  end

  test "security:lockdown and security:lift_lockdown" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("security:lockdown")
    ENV["HOURS"] = "2"
    assert_output(/lockdown for 2.0 hours/) { Rake::Task["security:lockdown"].tap(&:reenable).invoke }
    assert AbuseProtection.lockdown?
    assert_output(/Lockdown lifted/) { Rake::Task["security:lift_lockdown"].tap(&:reenable).invoke }
    assert_not AbuseProtection.lockdown?
  ensure
    ENV.delete("HOURS")
  end
end
