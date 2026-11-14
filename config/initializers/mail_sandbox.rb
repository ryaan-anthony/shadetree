# Staging mail goes only to allow-listed addresses (MailSandbox, PLT-09).
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(MailSandbox) if MailSandbox.enabled?
end
