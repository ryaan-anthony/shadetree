# Billable usage (BIL-02), for operators until the operator console shows it (OPS-02):
#   bin/rails usage:history BUSINESS=<uid> [PERIODS=24]   # quotes sent per period
namespace :usage do
  desc "Quotes sent per usage period for BUSINESS=uid (PERIODS=24)"
  task history: :environment do
    abort "Give BUSINESS=<uid>" if ENV["BUSINESS"].blank?
    business = Business.find_by!(uid: ENV["BUSINESS"])
    entitlements = business.entitlements
    puts "#{business.name} (#{business.plan.name}): #{entitlements.used(:quotes_sent)} of #{entitlements.limit(:quotes_sent) || "unlimited"} this period"
    entitlements.period.history(count: ENV.fetch("PERIODS", "24").to_i).each do |period|
      span = period.billing_cycle? ? "#{period.starts_at.to_fs(:db)} – #{period.ends_at.to_fs(:db)} (billing cycle)" : "#{period.starts_at.strftime("%B %Y")}"
      puts "  #{span}: #{period.used}"
    end
  end
end
