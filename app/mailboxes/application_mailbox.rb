# OPS-05: the only email the app receives is mail to the support address, posted by the
# Cloudflare Email Worker; Inbound::SupportEmailsController refuses any other recipient.
class ApplicationMailbox < ActionMailbox::Base
  routing all: :support
end
