# OPS-01: operator access from the command line, for the first operator and for recovering a
# locked-out one. Both are recorded in the audit log as done from the command line.
#   bin/rails ops:grant EMAIL=founder@example.com
#   bin/rails ops:reset_two_factor EMAIL=founder@example.com REASON="lost phone"
namespace :ops do
  def ops_user!
    abort "Give EMAIL=" if ENV["EMAIL"].blank?
    User.find_by(email: ENV["EMAIL"].strip.downcase) or abort "No user with that email. They need to sign up first."
  end

  desc "Give an existing user operator access: EMAIL="
  task grant: :environment do
    user = ops_user!
    next puts("#{user.email} is already an operator.") if Operator.for(user)

    Operator.grant!(user)
    AuditEntry.record!(operator: nil, operator_email: "command line", action: "operator.granted", user:, reason: ENV["REASON"].presence)
    OperatorMailer.with(user:).granted.deliver_later
    puts "#{user.email} is an operator. They'll set up two-factor the first time they open /ops."
  end

  desc "Clear an operator's two-factor so they set it up again (a lost phone): EMAIL= REASON="
  task reset_two_factor: :environment do
    user = ops_user!
    operator = Operator.for(user) or abort "#{user.email} isn't an operator."
    abort "Give REASON= (it goes in the audit log)" if ENV["REASON"].blank?

    operator.reset_two_factor!
    AuditEntry.record!(operator: nil, operator_email: "command line", action: "operator.two_factor_reset", user:, reason: ENV["REASON"])
    OperatorMailer.with(user:).two_factor_reset.deliver_later
    puts "#{user.email} will set up two-factor again the next time they open /ops."
  end
end
