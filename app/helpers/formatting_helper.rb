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

  # local_time_ago(client.last_activity_at) => "3 days ago", with the exact local time as a
  # tooltip and in the datetime attribute.
  def local_time_ago(time, zone: Time.zone)
    return if time.nil?

    tag.time("#{time_ago_in_words(time)} ago", datetime: time.utc.iso8601, title: l(time.in_time_zone(zone)))
  end

  # Date-only values (due dates, closures) have no zone and are never shifted.
  def local_date(date, format: :default)
    return if date.nil?

    tag.time(l(date.to_date, format:), datetime: date.to_date.iso8601)
  end

  # phone_number("2155551212")      => "(215) 555-1212"
  # phone_number("+1 215-555-1212") => "(215) 555-1212"
  # North American numbers (10 digits, or 11 with a leading 1) get the usual format; anything
  # else (international numbers, extensions) is shown as typed.
  def phone_number(value)
    digits = north_american_digits(value)
    digits ? "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}" : value.to_s.strip.presence
  end

  # The tel: href: +1 and ten digits for North American numbers, otherwise the digits (keeping
  # a leading +), so phones dial it whatever punctuation was typed. Extensions are left off.
  def phone_href(value)
    number = value.to_s.strip[/\A[^a-z]*/i].strip # an extension isn't dialled
    digits = north_american_digits(number)
    return "tel:+1#{digits}" if digits

    "tel:#{number.start_with?("+") ? "+" : ""}#{number.gsub(/\D/, "")}"
  end

  # A tel: link showing the formatted number (or the block's content).
  def phone_link(value, **attributes, &)
    return if value.blank?

    block_given? ? link_to(phone_href(value), **attributes, &) : link_to(phone_number(value), phone_href(value), **attributes)
  end

  private

  def north_american_digits(value)
    text = value.to_s.strip
    return if text.match?(/[a-z]/i) # extensions ("x12", "ext. 4") and anything that isn't just a number

    digits = text.gsub(/\D/, "")
    if text.start_with?("+") then digits[1..] if digits.length == 11 && digits.start_with?("1")
    elsif digits.length == 11 && digits.start_with?("1") then digits[1..]
    elsif digits.length == 10 then digits
    end
  end
end
