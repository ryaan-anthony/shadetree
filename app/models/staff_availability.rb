# Staff scheduling availability.
#
# The StaffAvailability model represents staff scheduling availability
# for staff members within businesses. Each record defines when a staff
# member is available to work on specific days of the week, with optional
# location assignments for multi-location businesses.
#
# @attr [Integer] staff_member_id Associated staff member (foreign key, required)
# @attr [Integer] day_of_week Day of week - 0-6 (Sunday-Saturday) (required)
# @attr [Time] start_time Available start time (required)
# @attr [Time] end_time Available end time (required)
# @attr [Integer] location_id Location assignment (foreign key, optional)
# @attr [Boolean] is_available Availability flag (default: true)
class StaffAvailability < ApplicationRecord
  # Relationships
  belongs_to :staff_member
  belongs_to :location, optional: true

  # Validations
  validates :staff_member_id, presence: true
  validates :day_of_week, presence: true, inclusion: { in: 0..6 }
  validates :start_time, presence: true
  validates :end_time, presence: true
  validate :end_time_after_start_time
  validates :staff_member_id, uniqueness: {
    scope: [ :day_of_week, :location_id ],
    message: "already has availability set for this day and location"
  }

  # Scopes
  scope :available, -> { where(is_available: true) }
  scope :unavailable, -> { where(is_available: false) }
  scope :for_day, ->(day) { where(day_of_week: day) }
  scope :for_location, ->(location_id) { where(location_id: location_id) }
  scope :any_location, -> { where(location_id: nil) }

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

  def available?
    is_available?
  end

  def unavailable?
    !is_available?
  end

  def hours_range
    return "Not available" unless is_available?
    return "Times not set" unless start_time && end_time

    "#{formatted_time(start_time)} - #{formatted_time(end_time)}"
  end

  def duration_in_hours
    return 0 unless is_available? && start_time && end_time

    # Handle times that cross midnight
    if end_time < start_time
      (24.hours - (start_time.hour * 3600 + start_time.min * 60)) +
      (end_time.hour * 3600 + end_time.min * 60)
    else
      end_time - start_time
    end / 1.hour
  end

  def available_at_time?(time)
    return false unless is_available? || !start_time || !end_time

    time_seconds = time.hour * 3600 + time.min * 60
    start_seconds = start_time.hour * 3600 + start_time.min * 60
    end_seconds = end_time.hour * 3600 + end_time.min * 60

    if end_seconds < start_seconds # Crosses midnight
      time_seconds >= start_seconds || time_seconds <= end_seconds
    else
      time_seconds >= start_seconds && time_seconds <= end_seconds
    end
  end

  def location_assignment
    location ? location.name : "Any location"
  end

  def staff_name
    staff_member.full_name
  end

  def business
    staff_member.business
  end

  def availability_description
    status = is_available? ? "Available" : "Not available"
    location_text = location ? " at #{location.name}" : " (any location)"
    "#{day_name}: #{status} #{hours_range}#{location_text}"
  end

  def overlaps_with?(other_availability)
    return false unless other_availability.is_a?(StaffAvailability)
    return false unless day_of_week == other_availability.day_of_week
    return false unless is_available? && other_availability.is_available?

    # Check if both have times set
    return false unless start_time && end_time && other_availability.start_time && other_availability.end_time

    # Simple overlap check (not accounting for midnight crossing in this basic version)
    start_seconds = start_time.hour * 3600 + start_time.min * 60
    end_seconds = end_time.hour * 3600 + end_time.min * 60
    other_start = other_availability.start_time.hour * 3600 + other_availability.start_time.min * 60
    other_end = other_availability.end_time.hour * 3600 + other_availability.end_time.min * 60

    start_seconds < other_end && end_seconds > other_start
  end

  private

  def end_time_after_start_time
    nil unless start_time && end_time

    # Allow times that cross midnight (e.g., 10 PM to 6 AM)
    # This is valid for staff working overnight shifts
  end

  def formatted_time(time)
    time.strftime("%I:%M %p")
  end
end
