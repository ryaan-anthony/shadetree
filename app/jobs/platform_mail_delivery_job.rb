# Delivers platform email (sign-up confirmation, password reset, invitations) in the background
# (NTF-01), so a slow mail server never holds up a request. Arguments aren't logged: they
# carry confirmation and reset tokens.
class PlatformMailDeliveryJob < ActionMailer::MailDeliveryJob
  include ReportsUnhandledErrors # PLT-10
  self.log_arguments = false
  retry_on Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::SMTPServerBusy,
           wait: :polynomially_longer, attempts: 5
end
