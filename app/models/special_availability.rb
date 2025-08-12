# Extended hours and special availability windows per location.
#
# The SpecialAvailability model represents extended hours and special availability
# windows for business locations. This allows businesses to define specific dates
# when they have extended hours or special availability outside their normal
# operating schedule.
#
# @attr [Integer] location_id Associated location (foreign key, required)
# @attr [Date] date Special availability date (required)
# @attr [Time] start_time Start time (required)
# @attr [Time] end_time End time (required)
# @attr [String] reason Availability reason (required)
class SpecialAvailability < ApplicationRecord
  # Relationships
  belongs_to :location

  # Validations
  validates :location_id, presence: true
  validates :date, presence: true
  validates :start_time, presence: true
  validates :end_time, presence: true
  validates :reason, presence: true
  validate :end_time_after_start_time
  validates :date, uniqueness: { scope: :location_id, message: "already has special availability for this location" }

  # Scopes
  scope :for_date, ->(date) { where(date: date) }
  scope :upcoming, -> { where('date >= ?', Date.current) }
  scope :past, -> { where('date < ?', Date.current) }
  scope :this_week, -> { where(date: Date.current.beginning_of_week..Date.current.end_of_week) }
  scope :this_month, -> { where(date: Date.current.beginning_of_month..Date.current.end_of_month) }

  # Instance methods
  def availability_description
    "Extended hours: #{formatted_time(start_time)} - #{formatted_time(end_time)} - #{reason}"
  end

  def hours_range
    return 'Times not set' unless start_time && end_time

    "#{formatted_time(start_time)} - #{formatted_time(end_time)}"
  end

  def duration_in_hours
    return 0 unless start_time && end_time

    # Handle times that cross midnight
    if end_time < start_time
      (24.hours - (start_time.hour * 3600 + start_time.min * 60)) +
      (end_time.hour * 3600 + end_time.min * 60)
    else
      end_time - start_time
    end / 1.hour
  end

  def open_at_time?(time)
    return false unless start_time && end_time

    time_seconds = time.hour * 3600 + time.min * 60
    start_seconds = start_time.hour * 3600 + start_time.min * 60
    end_seconds = end_time.hour * 3600 + end_time.min * 60

    if end_seconds < start_seconds # Crosses midnight
      time_seconds >= start_seconds || time_seconds <= end_seconds
    else
      time_seconds >= start_seconds && time_seconds <= end_seconds
    end
  end

  def overlaps_with_operating_hours?
    operating_hours = location.operating_hours.for_day(date.wday)
    return false if operating_hours.empty?

    operating_hours.any? do |oh|
      next if oh.is_closed? || !oh.open_time || !oh.close_time

      # Check if special availability overlaps with regular hours
      regular_start = oh.open_time.hour * 3600 + oh.open_time.min * 60
      regular_end = oh.close_time.hour * 3600 + oh.close_time.min * 60
      special_start = start_time.hour * 3600 + start_time.min * 60
      special_end = end_time.hour * 3600 + end_time.min * 60

      # Simple overlap check (not accounting for midnight crossing in this basic version)
      special_start < regular_end && special_end > regular_start
    end
  end

  def extends_operating_hours?
    operating_hours = location.operating_hours.for_day(date.wday).first
    return true if operating_hours.nil? || operating_hours.is_closed?

    # Check if special availability extends beyond regular hours
    special_start = start_time.hour * 3600 + start_time.min * 60
    special_end = end_time.hour * 3600 + end_time.min * 60
    regular_start = operating_hours.open_time.hour * 3600 + operating_hours.open_time.min * 60
    regular_end = operating_hours.close_time.hour * 3600 + operating_hours.close_time.min * 60

    special_start < regular_start || special_end > regular_end
  end

  private

  def end_time_after_start_time
    return unless start_time && end_time

    # Allow times that cross midnight (e.g., 10 PM to 2 AM)
    # This is valid for extended hours, so we don't enforce end > start
    # since some special availability may extend past midnight
  end

  def formatted_time(time)
    time.strftime('%I:%M %p')
  end
end
