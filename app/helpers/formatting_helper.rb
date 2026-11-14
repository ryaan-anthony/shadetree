# Display helpers for money and time (ADR 0013). Staff requests run in the current business's
# zone (Admin::BaseController), so times passed here are shown in that zone.
module FormattingHelper
  # money(quote.total) => "$1,250.00"; nil renders blank.
  def money(amount, zero: nil)
    amount&.format(display_zero_as: zero)
  end

  # local_time(visit.starts_at)               => "Mar 8, 2026, 9:00 AM"
  # local_time(visit.starts_at, format: :time) => "9:00 AM"
  # Wrapped in <time datetime="…UTC…"> so the exact instant is machine-readable.
  def local_time(time, format: :default, zone: Time.zone)
    return if time.nil?

    local = time.in_time_zone(zone)
    tag.time(l(local, format:), datetime: time.utc.iso8601)
  end

  # Date-only values (due dates, closures) have no zone and are never shifted.
  def local_date(date, format: :default)
    return if date.nil?

    tag.time(l(date.to_date, format:), datetime: date.to_date.iso8601)
  end
end
