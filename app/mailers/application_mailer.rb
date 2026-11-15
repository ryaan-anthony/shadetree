class ApplicationMailer < ActionMailer::Base
  # Sending domain is pending (vision open question G8); set MAIL_FROM per environment.
  default from: ENV.fetch("MAIL_FROM", "Shadetree <no-reply@getshadetree.com>")
  layout "mailer"
end
