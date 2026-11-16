class ApplicationMailer < ActionMailer::Base
  # The platform sender on the root sending domain (ADR 0017); set MAIL_FROM per environment.
  default from: ENV.fetch("MAIL_FROM", "Shadetree <no-reply@getshadetree.com>")
  layout "mailer"

  # A Message-ID on the sending domain (Mail would otherwise use the container's hostname).
  after_action { message.message_id = "<#{SecureRandom.uuid}@#{self.class.sending_domain}>" }

  def self.sending_domain = Mail::Address.new(default[:from]).domain
end
