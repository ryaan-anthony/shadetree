# Display helpers for money and time (ADR 0013). Staff requests run in the current business's
# zone (Admin::BaseController), so times passed here are shown in that zone.
#
# Dates (PLT-05 conventions): records, documents and emails always carry the year, as they're
# read later. Staff pages that look at now (today, this week, what's coming up) drop it while
# it's this year: friendly_date, or local_date/local_time with year: :auto. Pages with times on
# one day name the zone once ("Times in #{time_zone_label}"), never on each time.
module FormattingHelper
  YEARLESS = { date: { default: "%b %-d", long: "%A, %B %-d", weekday: "%a, %b %-d" },
               time: { default: "%b %-d, %-l:%M %p" } }.freeze
  # money(quote.total) => "$1,250.00"; nil renders blank.
  def money(amount, zero: nil)
    amount&.format(display_zero_as: zero)
  end

  # local_time(visit.starts_at)               => "Mar 8, 2026, 9:00 AM"
  # local_time(visit.starts_at, format: :time) => "9:00 AM"
  # Wrapped in <time datetime="…UTC…"> so the exact instant is machine-readable.
  # year: :auto leaves the year off a time in this year (see above).
  def local_time(time, format: :default, zone: Time.zone, year: true)
    return if time.nil?

    local = time.in_time_zone(zone)
    text = year == :auto && local.year == today_for_dates.year && (pattern = YEARLESS[:time][format]) ? local.strftime(pattern) : l(local, format:)
    tag.time(text, datetime: time.utc.iso8601)
  end

  # local_time_ago(client.last_activity_at) => "3 days ago", with the exact local time as a
  # tooltip and in the datetime attribute.
  def local_time_ago(time, zone: Time.zone)
    return if time.nil?

    tag.time("#{time_ago_in_words(time)} ago", datetime: time.utc.iso8601, title: l(time.in_time_zone(zone)))
  end

  # Date-only values (due dates, closures) have no zone and are never shifted.
  def local_date(date, format: :default, year: true)
    return if date.nil?
    return friendly_date(date, format:, year:) if year != true

    tag.time(l(date.to_date, format:), datetime: date.to_date.iso8601)
  end

  # phone_number("2155551212")      => "(215) 555-1212"
  # phone_number("+1 215-555-1212") => "(215) 555-1212"
  # North American numbers (10 digits, or 11 with a leading 1) get the usual format; anything
  # else (international numbers, extensions, vanity numbers) is shown as typed.
  def phone_number(value)
    text = value.to_s.strip
    number = phone_number_part(text)
    digits = north_american_digits(number) unless number.match?(/[a-z]/i) || number != text
    digits ? "(#{digits[0, 3]}) #{digits[3, 3]}-#{digits[6, 4]}" : text.presence
  end

  PHONE_MIN_DIGITS = 7
  PHONE_MAX_DIGITS = 15 # E.164
  KEYPAD = %w[ABC DEF GHI JKL MNO PQRS TUV WXYZ].each_with_index.to_h { |letters, index| [ letters, (index + 2).to_s ] }.freeze

  # The tel: href, or nil when there's no single number to dial (fewer than 7 digits, "call us",
  # or more than 15, like two numbers in one field). Text before the first digit or + is a label
  # ("Office: ") and is skipped.
  # Extensions are left off (from x, ext, #, comma or semicolon) and vanity letters become keypad
  # digits ("1-800-GOT-JUNK" => tel:+18004685865). North American numbers get +1 and ten digits.
  # Other countries are best effort: a leading + is kept and the rest is digits, but a trunk 0
  # isn't removed, and ten digits without a + are taken as a US number.
  def phone_href(value)
    number = phone_number_part(value.to_s.strip)[/[\d+].*/m].to_s # letters only count after the number starts
    keyed = number.upcase.gsub(/[A-Z]/) { |letter| KEYPAD.find { |letters, _| letters.include?(letter) }.last }
    digits = keyed.gsub(/\D/, "")
    return unless digits.length.between?(PHONE_MIN_DIGITS, PHONE_MAX_DIGITS)

    us = north_american_digits(keyed)
    us ? "tel:+1#{us}" : "tel:#{keyed.start_with?("+") ? "+" : ""}#{digits}"
  end

  # A tel: link showing the formatted number (or the block's content); plain text when there's
  # nothing to dial.
  def phone_link(value, **attributes, &)
    return if value.blank?

    href = phone_href(value)
    return (block_given? ? capture(&) : phone_number(value)) unless href

    block_given? ? link_to(href, **attributes, &) : link_to(phone_number(value), href, **attributes)
  end

  # friendly_date(Date.new(2026, 11, 20))                 => "Friday, November 20" (this year)
  # friendly_date(Date.new(2027, 1, 4), format: :weekday) => "Mon, Jan 4, 2027"
  # year: :auto (the default) shows it only outside this year; false never (today and this
  # week's pages, where a week can span New Year); true always (an ambiguous context).
  def friendly_date(date, format: :long, year: :auto)
    return if date.nil?

    date = date.to_date
    pattern = YEARLESS[:date].fetch(format) { raise ArgumentError, "Unknown date format #{format.inspect}" }
    show_year = year == :auto ? date.year != today_for_dates.year : year
    tag.time(date.strftime(show_year ? "#{pattern}, %Y" : pattern), datetime: date.iso8601)
  end

  # "Eastern Time (US & Canada)": a zone by the name people pick it by in Settings.
  def time_zone_label(zone = Time.zone)
    zone = ActiveSupport::TimeZone[zone] unless zone.is_a?(ActiveSupport::TimeZone)
    ActiveSupport::TimeZone::MAPPING.key(zone.tzinfo.identifier) || zone.name.split("/").last.tr("_", " ")
  end

  private

  # The part of a phone number that's dialled: everything before an extension marker.
  def phone_number_part(text)
    text.split(/[#,;]|(?:\b|(?<=\d))(?:ext(?:ension)?\.?|x)\s*\d/i, 2).first.to_s.strip
  end

  def north_american_digits(text)
    digits = text.gsub(/\D/, "")
    if text.start_with?("+") then digits[1..] if digits.length == 11 && digits.start_with?("1")
    elsif digits.length == 11 && digits.start_with?("1") then digits[1..]
    elsif digits.length == 10 then digits
    end
  end

  def today_for_dates = (respond_to?(:current_business, true) && current_business&.today) || Time.zone.today
end
