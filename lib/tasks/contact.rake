# MKT-02: honoring a request to forget someone who wrote through the contact form, until the
# operator console has a button for it.
namespace :contact do
  desc "Delete every contact message from an email address (EMAIL=...)"
  task erase: :environment do
    email = ENV.fetch("EMAIL") { abort "Usage: bin/rails contact:erase EMAIL=person@example.com" }
    puts "Deleted #{ContactMessage.erase_for!(email)} message(s)."
  end
end
