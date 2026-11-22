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

  # ACC-08: how the guided tour's first run went for the Owners it was offered to, beside their
  # time to a first quote. Counts and minutes only; nothing about who.
  desc "How the guided tour went for new Owners: finished, skipped (and where), with time to first quote"
  task tour: :environment do
    owners = BusinessUser.owners.where.not(tour_offered_at: nil).includes(:business)
    if owners.none?
      puts "The tour hasn't been offered yet."
      next
    end
    owners.group_by { _1.tour_status }.sort_by { _1.to_s }.each do |status, group|
      minutes = group.filter_map { _1.business.seconds_to_first_quote }.sort
      median = minutes.any? ? "#{(minutes[(minutes.size - 1) / 2] / 60.0).round(1)} min to first quote (median of #{minutes.size})" : "no quotes sent yet"
      puts "#{status}: #{group.size}. #{median}."
    end
    replayed = owners.count { _1.tour_replayed_at }
    puts "Taken again from Help after the first run: #{replayed}." if replayed.positive?
    stops = owners.select { _1.tour_status.in?(%w[skipped started]) }.map(&:tour_stop).tally.sort_by { -_2 }
    puts "Ended or left at: #{stops.map { "#{_1} #{_2}" }.join(", ")}." if stops.any?
  end
end
