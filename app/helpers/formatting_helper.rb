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

  def today_for_dates = (respond_to?(:current_business, true) && current_business&.today) || Time.zone.today
end
