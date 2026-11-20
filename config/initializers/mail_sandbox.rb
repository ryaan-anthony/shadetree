# With MAIL_SANDBOX=true, mail goes only to allow-listed addresses (MailSandbox, PLT-09). Off by default.
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(MailSandbox) if MailSandbox.enabled?
end
