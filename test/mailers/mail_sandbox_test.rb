require "test_helper"

class MailSandboxTest < ActiveSupport::TestCase
  def build_mail(to:, cc: nil, subject: "Your quote")
    Mail.new(to:, cc:, subject:, from: "no-reply@example.com", body: "hi")
  end

  def with_env(values)
    previous = values.keys.to_h { [ _1, ENV[_1] ] }
    values.each { ENV[_1] = _2 }
    yield
  ensure
    previous.each { ENV[_1] = _2 }
  end

  test "allow-listed addresses and domains get their mail unchanged" do
    with_env("MAIL_ALLOWLIST" => "owner@example.com, @shadetree-team.test") do
      mail = build_mail(to: [ "owner@example.com", "dev@shadetree-team.test" ])
      MailSandbox.delivering_email(mail)
      assert_equal [ "owner@example.com", "dev@shadetree-team.test" ], mail.to
      assert_equal "Your quote", mail.subject
    end
  end

  test "real client addresses are redirected to the sandbox inbox" do
    with_env("MAIL_ALLOWLIST" => "@shadetree-team.test", "MAIL_SANDBOX_TO" => "sandbox@shadetree-team.test") do
      mail = build_mail(to: [ "client@gmail.com" ], cc: [ "boss@client.com" ])
      MailSandbox.delivering_email(mail)
      assert_equal [ "sandbox@shadetree-team.test" ], mail.to
      assert_nil mail.cc
      assert_match "client@gmail.com, boss@client.com", mail.subject
      assert mail.perform_deliveries
    end
  end

  test "with no sandbox inbox, blocked mail isn't sent at all" do
    with_env("MAIL_ALLOWLIST" => "", "MAIL_SANDBOX_TO" => "") do
      mail = build_mail(to: [ "client@gmail.com" ])
      MailSandbox.delivering_email(mail)
      assert_not mail.perform_deliveries
    end
  end

  test "enabled only when MAIL_SANDBOX is true" do
    with_env("MAIL_SANDBOX" => "true") { assert MailSandbox.enabled? }
    with_env("MAIL_SANDBOX" => nil) { assert_not MailSandbox.enabled? }
  end
end
