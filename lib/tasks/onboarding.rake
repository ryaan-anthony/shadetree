# ACC-05: the time-to-first-quote metric, across businesses (no personal data).
namespace :onboarding do
  desc "How long businesses take from setup to their first quote sent (median and quartiles)"
  task time_to_first_quote: :environment do
    seconds = Business.where.not(first_quote_sent_at: nil).map(&:seconds_to_first_quote).sort
    if seconds.empty?
      puts "No business has sent a quote yet."
    else
      at = ->(fraction) { (seconds[((seconds.size - 1) * fraction).round] / 60.0).round(1) }
      puts "#{seconds.size} businesses. Minutes to first quote: 25% #{at.(0.25)}, median #{at.(0.5)}, 75% #{at.(0.75)}."
    end
  end
end
