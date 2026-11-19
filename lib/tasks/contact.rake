# MKT-02: honoring a request to forget someone who wrote through the contact form (the operator
# console has the same button on each message). Recorded in the audit log, without the address.
namespace :contact do
  desc "Delete every contact message from an email address (EMAIL=...)"
  task erase: :environment do
    email = ENV.fetch("EMAIL") { abort "Usage: bin/rails contact:erase EMAIL=person@example.com" }
    count = ContactMessage.erase_for!(email)
    AuditEntry.record!(operator: nil, operator_email: "command line", action: "contact_message.erased", count:)
    puts "Deleted #{count} message(s)."
  end
end
