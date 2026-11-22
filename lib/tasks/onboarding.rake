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
  # time to a first quote. Counts and minutes only; nothing about who. Owners offered it when
  # they created the business are measured from its creation (ACC-05); Owners of businesses
  # that existed before it (offered later, 2026-11-22) are reported apart, from the offer, so
  # they don't skew the new businesses' medians.
  desc "How the guided tour went: finished, skipped (and where), with time to first quote; new and existing businesses apart"
  task tour: :environment do
    owners = BusinessUser.owners.where.not(tour_offered_at: nil).includes(:business)
    if owners.none?
      puts "The tour hasn't been offered yet."
      next
    end
    # An offer within the hour of the business's creation is its creator's.
    fresh, existing = owners.partition { _1.tour_offered_at < _1.business.created_at + 1.hour }
    report = lambda do |heading, group, seconds|
      next if group.empty?

      puts heading
      group.group_by(&:tour_status).sort_by { _1.to_s }.each do |status, members|
        times = members.filter_map(&seconds).sort
        median = times.any? ? "#{(times[(times.size - 1) / 2] / 60.0).round(1)} min to first quote (median of #{times.size})" : "no quotes sent yet"
        puts "  #{status}: #{members.size}. #{median}."
      end
    end
    report.("New businesses (offered when created; minutes from creation):", fresh, ->(m) { m.business.seconds_to_first_quote })
    report.("Existing businesses (offered later; minutes from the offer, first quotes after it only):", existing,
            ->(m) { (sent = m.business.first_quote_sent_at) && sent > m.tour_offered_at ? (sent - m.tour_offered_at).round : nil })
    replayed = owners.count { _1.tour_replayed_at }
    puts "Taken again from Help after the first run: #{replayed}." if replayed.positive?
    stops = owners.select { _1.tour_status.in?(%w[skipped started]) }.map(&:tour_stop).tally.sort_by { -_2 }
    puts "Ended or left at: #{stops.map { "#{_1} #{_2}" }.join(", ")}." if stops.any?
  end
end
