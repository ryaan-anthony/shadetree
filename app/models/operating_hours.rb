# Location-specific weekly operating hours.
#
# The OperatingHours model represents weekly operating hours for business
# locations. Each record defines the hours for a specific day of the week
# at a particular location, allowing businesses to set different hours
# for different locations and handle closed days.
#
# @attr [Integer] location_id Associated location (foreign key, required)
# @attr [Integer] day_of_week Day of week - 0-6 (Sunday-Saturday) (required)
# @attr [Time] open_time Opening time
# @attr [Time] close_time Closing time
# @attr [Boolean] is_closed Closed all day flag (default: false)
class OperatingHours < ApplicationRecord
  # Relationships
  belongs_to :location

  # Validations
  validates :location_id, presence: true
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :open_time, presence: true, unless: :is_closed?
  validates :close_time, presence: true, unless: :is_closed?
  validate :close_time_after_open_time, unless: :is_closed?
  validates :location_id, uniqueness: { scope: :day_of_week, message: "already has operating hours for this day" }

  # Scopes
  scope :open_days, -> { where(is_closed: false) }
  scope :closed_days, -> { where(is_closed: true) }
  scope :for_day, ->(day) { where(day_of_week: day) }

  # Constants
  DAYS_OF_WEEK = {
    0 => "Sunday",
    1 => "Monday",
    2 => "Tuesday",
    3 => "Wednesday",
    4 => "Thursday",
    5 => "Friday",
    6 => "Saturday"
  }.freeze

  # Instance methods
  def day_name
    DAYS_OF_WEEK[day_of_week]
  end

  def open?
    !is_closed?
  end

  def closed?
    is_closed?
  end

  def hours_range
    return "Closed" if is_closed?
    return "Hours not set" unless open_time && close_time

    "#{formatted_time(open_time)} - #{formatted_time(close_time)}"
  end

  def duration_in_hours
    return 0 if is_closed? || !open_time || !close_time

    # Handle times that cross midnight
    if close_time < open_time
      (24.hours - (open_time.hour * 3600 + open_time.min * 60)) +
      (close_time.hour * 3600 + close_time.min * 60)
    else
      close_time - open_time
    end / 1.hour
  end

  def open_at_time?(time)
    return false if is_closed? || !open_time || !close_time

    time_seconds = time.hour * 3600 + time.min * 60
    open_seconds = open_time.hour * 3600 + open_time.min * 60
    close_seconds = close_time.hour * 3600 + close_time.min * 60

    if close_seconds < open_seconds # Crosses midnight
      time_seconds >= open_seconds || time_seconds <= close_seconds
    else
      time_seconds >= open_seconds && time_seconds <= close_seconds
    end
  end

  private

  def close_time_after_open_time
    nil unless open_time && close_time

    # Allow times that cross midnight (e.g., 10 PM to 2 AM)
    # This is valid, so we don't need to validate that close > open
    # since some businesses operate past midnight
  end

  def formatted_time(time)
    time.strftime("%I:%M %p")
  end
end
