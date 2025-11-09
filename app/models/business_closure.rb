# Special closures and holiday schedules per location.
#
# The BusinessClosure model represents special closures and holiday schedules
# for business locations. This allows businesses to define specific dates when
# they are closed, have modified hours, or have special scheduling needs.
#
# @attr [Integer] location_id Associated location (foreign key, required)
# @attr [Date] date Closure date (required)
# @attr [String] reason Closure reason (required)
# @attr [Boolean] is_full_day Full day closure flag (default: true)
# @attr [Time] modified_open_time Modified opening time
# @attr [Time] modified_close_time Modified closing time
# @attr [Boolean] is_recurring Annual recurrence flag (default: false)
class BusinessClosure < ApplicationRecord
  # Relationships
  belongs_to :location

  # Validations
  validates :location_id, presence: true
  validates :date, presence: true
  validates :reason, presence: true
  validates :modified_open_time, presence: true, unless: :is_full_day?
  validates :modified_close_time, presence: true, unless: :is_full_day?
  validate :modified_close_time_after_open_time, unless: :is_full_day?
  validates :date, uniqueness: { scope: :location_id, message: "already has a closure for this location" }

  # Scopes
  scope :full_day_closures, -> { where(is_full_day: true) }
  scope :modified_hours, -> { where(is_full_day: false) }
  scope :recurring, -> { where(is_recurring: true) }
  scope :one_time, -> { where(is_recurring: false) }
  scope :for_date, ->(date) { where(date: date) }
  scope :upcoming, -> { where("date >= ?", Date.current) }
  scope :past, -> { where("date < ?", Date.current) }

  # Instance methods
  def full_day_closure?
    is_full_day?
  end

  def modified_hours?
    !is_full_day?
  end

  def recurring_closure?
    is_recurring?
  end

  def one_time_closure?
    !is_recurring?
  end

  def closure_description
    if is_full_day?
      "Closed all day - #{reason}"
    else
      "Modified hours: #{formatted_time(modified_open_time)} - #{formatted_time(modified_close_time)} - #{reason}"
    end
  end

  def hours_range
    return "Closed all day" if is_full_day?
    return "Modified hours not set" unless modified_open_time && modified_close_time

    "#{formatted_time(modified_open_time)} - #{formatted_time(modified_close_time)}"
  end

  def duration_in_hours
    return 0 if is_full_day? || !modified_open_time || !modified_close_time

    # Handle times that cross midnight
    if modified_close_time < modified_open_time
      (24.hours - (modified_open_time.hour * 3600 + modified_open_time.min * 60)) +
      (modified_close_time.hour * 3600 + modified_close_time.min * 60)
    else
      modified_close_time - modified_open_time
    end / 1.hour
  end

  def open_at_time?(time)
    return false if is_full_day? || !modified_open_time || !modified_close_time

    time_seconds = time.hour * 3600 + time.min * 60
    open_seconds = modified_open_time.hour * 3600 + modified_open_time.min * 60
    close_seconds = modified_close_time.hour * 3600 + modified_close_time.min * 60

    if close_seconds < open_seconds # Crosses midnight
      time_seconds >= open_seconds || time_seconds <= close_seconds
    else
      time_seconds >= open_seconds && time_seconds <= close_seconds
    end
  end

  def next_occurrence
    return nil unless is_recurring?
    return nil if date < Date.current

    # For recurring closures, calculate next year's occurrence
    next_year = Date.current.year + 1
    Date.new(next_year, date.month, date.day)
  rescue Date::Error
    # Handle leap year edge cases (e.g., Feb 29)
    nil
  end

  private

  def modified_close_time_after_open_time
    nil unless modified_open_time && modified_close_time

    # Allow times that cross midnight (e.g., 10 PM to 2 AM)
    # This is valid for some special hours, so we don't enforce close > open
  end

  def formatted_time(time)
    time.strftime("%I:%M %p")
  end
end
