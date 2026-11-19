# Billable usage (BIL-02), for operators until the operator console shows it (OPS-02):
#   bin/rails usage:history BUSINESS=<uid>   # quotes sent per period, last 24 periods
namespace :usage do
  desc "Quotes sent per usage period for BUSINESS=uid (MONTHS=24)"
  task history: :environment do
    business = Business.find_by!(uid: ENV.fetch("BUSINESS"))
    entitlements = business.entitlements
    puts "#{business.name} (#{business.plan.name}): #{entitlements.used(:quotes_sent)} of #{entitlements.limit(:quotes_sent) || "unlimited"} this period"
    entitlements.period.history(count: ENV.fetch("MONTHS", "24").to_i).each do |period|
      puts "  #{period.starts_at.to_date} – #{period.ends_at.to_date - 1}: #{period.used}"
    end
  end
end
