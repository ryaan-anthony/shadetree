# One trip to do a job's work (JOB-02), on one date: at a start time, in an arrival window
# ("arrive 8–10"), or anytime that day; with an estimated duration, the members going, and its
# own instructions. Times are entered as wall-clock times in the business's zone and stored in
# UTC; a visit's times are always on its own date there.
#
# Changes go through #reschedule!, #cancel!, #restore! and #complete!, which record who did
# what (VisitEvent) and update the job's status (Job#refresh_status!).
class Visit < ApplicationRecord
  include BusinessOwned

  TIMINGS = %w[exact window anytime].freeze
  STATUSES = %w[scheduled in_progress completed cancelled].freeze
  OPEN_STATUSES = %w[scheduled in_progress].freeze
  LABELS = { "scheduled" => "Scheduled", "in_progress" => "In progress", "completed" => "Done", "cancelled" => "Cancelled" }.freeze
  MAX_DURATION = 24 * 60
  CLOCK = /\A([01]\d|2[0-3]):[0-5]\d(:00)?\z/ # "HH:MM" from a time field (browsers may add ":00")

  class NotOpen < StandardError; end

  belongs_to_business_record :job
  belongs_to :created_by, class_name: "User", optional: true
  has_many :assignments, class_name: "VisitAssignment", inverse_of: :visit, dependent: :delete_all
  has_many :assignees, -> { order(:first_name, :last_name, :email) }, through: :assignments, source: :user
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "VisitEvent", inverse_of: :visit, dependent: :delete_all

  normalizes :instructions, with: ->(value) { value.to_s.strip.presence }
  normalizes :cancel_reason, with: ->(value) { value.to_s.squish.presence }

  validates :scheduled_on, presence: true
  validates :timing, inclusion: { in: TIMINGS }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_minutes, numericality: { only_integer: true, in: 5..MAX_DURATION, message: "must be between 5 minutes and 24 hours" }
  validates :instructions, length: { maximum: 2_000 }
  validates :cancel_reason, length: { maximum: 200 }
  validate :times_make_sense
  validate :assignees_are_members

  before_validation :place_times

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :in_order, -> { order(:scheduled_on, Arel.sql("starts_at NULLS LAST"), :id) }
  scope :upcoming, ->(today) { open.where(scheduled_on: today..) }

  # Form fields: wall-clock times ("09:00") and the duration in hours ("1.5").
  attr_writer :start_time, :window_end_time

  def start_time = @start_time || clock(starts_at)
  def window_end_time = @window_end_time || clock(window_ends_at)

  def duration_hours = (duration_minutes.to_d / 60).round(2).to_s("F").sub(/\.0\z/, "")

  def duration_hours=(value)
    hours = BigDecimal(value.to_s.strip, exception: false)
    self.duration_minutes = hours && (hours * 60).round
  end

  # Members going, from the form's checkboxes (user ids). Checked against the business's
  # active members on validation.
  def assignee_ids=(ids)
    @assignee_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  def assignee_ids = @assignee_ids || assignments.map(&:user_id)

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)
  def anytime? = timing == "anytime"
  def window? = timing == "window"

  # When the work is expected to finish: the start (or the window's end) plus the duration.
  def ends_at = starts_at && ((window_ends_at || starts_at) + duration_minutes.minutes)

  # "9 am", "Arrive 8–10 am", "Anytime".
  def time_label
    case timing
    when "exact" then clock_label(starts_at)
    when "window" then "Arrive #{clock_label(starts_at, ampm: starts_at.strftime("%p") != window_ends_at.strftime("%p"))}–#{clock_label(window_ends_at)}"
    else "Anytime"
    end
  end

  # "Tue, Nov 17 · Arrive 8–10 am"
  def when_label = "#{scheduled_on.strftime("%a, %b %-d")}#{", #{scheduled_on.year}" if scheduled_on.year != business.today.year} · #{time_label}"

  def duration_label
    hours, minutes = duration_minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{minutes} min" if minutes.positive?) ].compact.join(" ")
  end

  # A new visit with its assignees, recorded and reflected in the job's status.
  def schedule!(by:)
    transaction do
      save!
      sync_assignments
      VisitEvent.record!(self, :scheduled, by:, when: when_label, crew: assignees.map(&:full_name))
      job.refresh_status!
    end
    self
  end

  # Date, time, duration, crew or instructions changed; records what moved and who changed.
  def reschedule!(attributes, by:)
    with_lock do
      raise NotOpen, "This visit is #{status_label.downcase}." unless open?

      before_when = when_label
      before_crew = assignees.to_a
      assign_attributes(attributes)
      save!
      sync_assignments
      after_crew = assignees.reload.to_a
      VisitEvent.record!(self, :rescheduled, by:, from: before_when, to: when_label) if when_label != before_when
      added, removed = after_crew - before_crew, before_crew - after_crew
      VisitEvent.record!(self, :reassigned, by:, added: added.map(&:full_name), removed: removed.map(&:full_name)) if added.any? || removed.any?
    end
    self
  end

  def cancel!(by:, reason: nil, refresh_job: true)
    with_lock do
      raise NotOpen, "This visit is already #{status_label.downcase}." unless open?

      update!(status: "cancelled", cancelled_at: Time.current, cancel_reason: reason)
      VisitEvent.record!(self, :cancelled, by:, reason:)
    end
    job.refresh_status! if refresh_job
    self
  end

  def restore!(by:)
    with_lock do
      raise NotOpen, "This visit isn't cancelled." unless status == "cancelled"
      raise NotOpen, "Reopen the job first." unless job.open?

      update!(status: "scheduled", cancelled_at: nil, cancel_reason: nil)
      VisitEvent.record!(self, :restored, by:)
    end
    job.refresh_status!
    self
  end

  # Done (staff here; technicians from their day view, JOB-04).
  def complete!(by:, refresh_job: true)
    with_lock do
      raise NotOpen, "This visit is #{status_label.downcase}." unless open?

      update!(status: "completed", completed_at: Time.current)
      VisitEvent.record!(self, :completed, by:)
    end
    job.refresh_status! if refresh_job
    self
  end

  private

  def clock(time) = time&.in_time_zone(business.time_zone)&.strftime("%H:%M")

  def clock_label(time, ampm: true)
    local = time.in_time_zone(business.time_zone)
    label = "#{(local.hour % 12).nonzero? || 12}#{":%02d" % local.min if local.min.positive?}"
    ampm ? "#{label} #{local.hour < 12 ? "am" : "pm"}" : label
  end

  # The form's wall-clock times on the visit's date, in the business's zone (so moving a visit to
  # another day keeps its clock time). A time that can't be read leaves none, and validation says so.
  def place_times
    return unless scheduled_on && business

    read = ->(value) { CLOCK.match?(value.to_s.strip) ? business.local_time(scheduled_on, value.to_s.strip.first(5)) : nil }
    self.starts_at = anytime? ? nil : read.(start_time)
    self.window_ends_at = window? ? read.(window_end_time) : nil
  end

  def times_make_sense
    case timing
    when "exact"
      errors.add(:start_time, "needs a time") unless starts_at
    when "window"
      errors.add(:start_time, "needs a time") unless starts_at
      errors.add(:window_end_time, "needs a time") unless window_ends_at
      errors.add(:window_end_time, "must be after the window starts") if starts_at && window_ends_at && window_ends_at <= starts_at
    end
  end

  def assignees_are_members
    return if @assignee_ids.nil? || @assignee_ids.empty?

    members = business.business_users.active.where(user_id: @assignee_ids).count
    errors.add(:assignee_ids, "must be members of your team") if members != @assignee_ids.size
  end

  def sync_assignments
    return if @assignee_ids.nil?

    current = assignments.map(&:user_id)
    assignments.where(user_id: current - @assignee_ids).delete_all
    (@assignee_ids - current).each { assignments.create!(user_id: _1) }
    assignments.reset
    assignees.reset
    @assignee_ids = nil
  end
end
