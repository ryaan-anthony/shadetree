# OPS-01: the first operator (later ones are granted in the console):
#   bin/rails ops:grant EMAIL=founder@example.com
namespace :ops do
  desc "Give an existing user operator access: EMAIL="
  task grant: :environment do
    abort "Give EMAIL=" if ENV["EMAIL"].blank?
    user = User.find_by(email: ENV["EMAIL"].strip.downcase) or abort "No user with that email. They need to sign up first."
    Operator.grant!(user)
    AuditEntry.record!(operator: user, action: "operator.granted", user:, reason: "Granted from the command line")
    puts "#{user.email} is an operator. They'll set up two-factor the first time they open /ops."
  end
end
