# CAT-06: a business's normal opening hours: one open range per weekday, or closed. Stored on
# businesses.weekly_hours as { "1" => { "opens" => "08:00", "closes" => "17:00" } } keyed by
# Date#wday; a missing weekday is closed, and NULL means the hours have never been set.
# Times are wall-clock times in the business's time zone. A day can't run past midnight, but
# can close at it: "00:00" as a closing time means the end of the day.
class WeeklyHours
  DAYS = [ 1, 2, 3, 4, 5, 6, 0 ].freeze # Monday first
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d(:00)?\z/ # browsers may add ":00" seconds
  WEEKDAYS_8_TO_5 = (1..5).to_h { [ _1.to_s, { "opens" => "08:00", "closes" => "17:00" } ] }.freeze

  def initialize(data)
    @data = data
  end

  def to_h = @data

  def set? = !@data.nil?

  # [opens, closes] as "HH:MM" for a weekday (Date#wday), or nil when closed or not set.
  def for(wday)
    day = @data&.dig(wday.to_s)
    [ day["opens"], day["closes"] ] if day
  end

  # Whether a weekday is marked open (even with a time still to fix).
  def open?(wday) = @data.is_a?(Hash) && @data.key?(wday.to_s)

  def self.normalize_clock(value) = value.to_s.strip.sub(/\A(\d\d:\d\d):00\z/, '\\1')
  def self.end_of_day?(clock) = clock == "00:00"


  # From the settings form: { "1" => { "open" => "1", "opens" => "08:00", "closes" => "17:00" } }.
  # Times for a day left closed are dropped.
  def self.from_form(params)
    days = DAYS.filter_map do |wday|
      day = params.to_h.fetch(wday.to_s, {})
      next unless ActiveModel::Type::Boolean.new.cast(day["open"])

      [ wday.to_s, { "opens" => normalize_clock(day["opens"]), "closes" => normalize_clock(day["closes"]) } ]
    end
    days.to_h
  end

  # What's wrong with the stored hours, as sentences ("Tuesday needs a closing time.").
  def problems = problems_by_day.values

  # The same, keyed by Date#wday, so the form can mark that day's fields.
  def problems_by_day
    return {} unless set?
    return { nil => "Hours aren't in the expected shape." } unless @data.is_a?(Hash) && @data.keys.all? { DAYS.map(&:to_s).include?(_1) }

    DAYS.filter_map { |wday|
      opens, closes = self.for(wday)
      next unless open?(wday)

      name = Date::DAYNAMES[wday]
      problem = if !CLOCK.match?(opens.to_s) then "#{name} needs an opening time."
      elsif !CLOCK.match?(closes.to_s) then "#{name} needs a closing time."
      elsif !self.class.end_of_day?(closes) && closes <= opens then "#{name} closes before it opens. Hours that run past midnight aren't supported."
      end
      [ wday, problem ] if problem
    }.to_h
  end

  # Days grouped by matching hours, for client pages: ["Mon–Fri 8 am–5 pm", "Sat 9 am–1 pm"].
  def summary
    return [] unless set?

    DAYS.chunk_while { |a, b| self.for(a) == self.for(b) }.filter_map do |run|
      range = self.for(run.first)
      next unless range

      days = run.size == 1 ? Date::ABBR_DAYNAMES[run.first] : "#{Date::ABBR_DAYNAMES[run.first]}–#{Date::ABBR_DAYNAMES[run.last]}"
      closes = self.class.end_of_day?(range[1]) ? "midnight" : self.class.clock_label(range[1])
      "#{days} #{self.class.clock_label(range[0])}–#{closes}"
    end
  end

  # "08:00" → "8 am", "17:30" → "5:30 pm".
  def self.clock_label(clock)
    hour, minute = clock.split(":").map { Integer(_1, 10) }
    "#{(hour % 12).nonzero? || 12}#{":%02d" % minute if minute.positive?} #{hour < 12 ? "am" : "pm"}"
  end
end
