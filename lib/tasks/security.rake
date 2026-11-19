# PLT-13: the escalation when bots get past the public forms' invisible checks. A lockdown makes
# sign-up, the request form and the contact form wait longer before accepting a submission and
# allow fewer attempts per IP address (AbuseProtection). It ends by itself.
#   bin/rails security:lockdown HOURS=24
#   bin/rails security:lift_lockdown
namespace :security do
  desc "Tighten public forms against bots for HOURS (default 24)"
  task lockdown: :environment do
    hours = Float(ENV.fetch("HOURS", "24"))
    AbuseProtection.lockdown!(hours:)
    tries, within = AbuseProtection::LOCKDOWN_ATTEMPTS
    puts "Public forms are in lockdown for #{hours} hours (#{AbuseProtection::LOCKDOWN_MIN_SECONDS}s wait, " \
         "#{tries} tries per IP per #{within.in_minutes.to_i} minutes). It's kept in the cache: clearing the cache ends it."
  end

  desc "End a lockdown early"
  task lift_lockdown: :environment do
    AbuseProtection.lift_lockdown!
    puts "Lockdown lifted#{" (FORMS_LOCKDOWN is still set in the environment)" if ENV["FORMS_LOCKDOWN"].present?}."
  end
end
