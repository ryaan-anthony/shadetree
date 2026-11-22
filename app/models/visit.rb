# One trip to do a job's work (JOB-02), on one date: at a start time, in an arrival window
# ("arrive 8–10"), or anytime that day; with an estimated duration, the members going, and its
# own instructions. Times are entered as wall-clock times in the business's zone and stored in
# UTC; a visit's times are always on its own date there.
#
# Changes go through #reschedule!, #cancel!, #restore! and #complete!, which record who did
# what (VisitEvent) and update the job's status (Job#refresh_status!).
class Visit < ApplicationRecord
  include BusinessOwned
  include ArrivalTiming # JOB-02's times, shared with request follow-ups (CLI-07)
  include SitePhotos # JOB-04's photos, shared with request follow-ups (JOB-06)

  STATUSES = %w[scheduled in_progress completed cancelled].freeze
  OPEN_STATUSES = %w[scheduled in_progress].freeze
  LABELS = { "scheduled" => "Scheduled", "in_progress" => "In progress", "completed" => "Completed", "cancelled" => "Cancelled" }.freeze

  MAX_DAYS = 31 # visits booked at once

  class NotOpen < StandardError; end
  class BadDates < ArgumentError; end

  belongs_to_business_record :job
  belongs_to :created_by, class_name: "User", optional: true

  def contact = job.contact # CAT-07: the job's location, for client pages and emails
  has_many :assignments, class_name: "VisitAssignment", inverse_of: :visit, dependent: :delete_all
  has_many :assignees, -> { order(:first_name, :last_name, :email) }, through: :assignments, source: :user
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "VisitEvent", inverse_of: :visit, dependent: :delete_all
  has_many :notes, -> { order(:created_at, :id) }, class_name: "VisitNote", inverse_of: :visit, dependent: :delete_all # JOB-04
  # JOB-04: photos from site, re-encoded without their metadata (phone photos carry GPS).
  has_many_attached :photos do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 320, 320 ], preprocessed: true
    attachable.variant :web, resize_to_limit: [ 1600, 1600 ]
  end

  MAX_PHOTOS = 30
  PHOTO_MAX_BYTES = 20.megabytes

  normalizes :instructions, with: ->(value) { value.to_s.strip.presence }
  normalizes :cancel_reason, with: ->(value) { value.to_s.squish.presence }

  validates :status, inclusion: { in: STATUSES }
  validates :instructions, length: { maximum: 2_000 }
  validates :client_note, length: { maximum: 1_000 } # JOB-05: for the client, in their emails and on their page
  validates :cancel_reason, length: { maximum: 200 }
  validate :assignees_are_members

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :scheduled, -> { where(status: "scheduled") }
  scope :in_order, -> { order(:scheduled_on, Arel.sql("starts_at NULLS LAST"), :id) }
  scope :upcoming, ->(today) { open.where(scheduled_on: today..) }

  # Members going, from the form's checkboxes (user ids). Checked against the business's
  # active members on validation.
  def assignee_ids=(ids)
    @assignee_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  def assignee_ids = @assignee_ids || assignments.map(&:user_id)

  # The crew from the form isn't a column, so a reload forgets it too (ArrivalTiming forgets the times).
  def reload(...)
    @assignee_ids = nil
    super
  end

  # Whether the time, day, duration or crew differ from what's saved (what warnings are about).
  # JOB-03: the changes for a visit moved on the calendar, for reschedule!. `on` is the new day;
  # `at` a new start ("HH:MM", a window keeps its length); `from`/`to` move it from one person
  # to another (nil for nobody); `crew`, when given, is everyone going (an undo puts it back).
  def move_attributes(on:, at: nil, from: nil, to: nil, crew: nil)
    attributes = { scheduled_on: on, **moved_time_attributes(at) }
    ids = assignee_ids
    ids = crew.map(&:to_i).uniq if crew
    ids = ((ids - [ from ]) | [ to ]).compact if crew.nil? && from != to
    attributes[:assignee_ids] = ids unless ids.sort == assignee_ids.sort
    attributes
  end

  def when_or_crew_changed?
    (changes.keys & %w[scheduled_on timing starts_at window_ends_at duration_minutes]).any? ||
      (!@assignee_ids.nil? && @assignee_ids.sort != assignments.map(&:user_id).sort)
  end

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)

  # A new visit with its assignees, recorded and reflected in the job's status.
  def schedule!(by:, notify_client: true) = self.class.schedule_all!([ self ], by:, notify_client:).first

  # After a visit opens again (booked, restored, reopened), finishing the job's visits tells the
  # office again; until then it's told once.
  def reset_ready_to_invoice
    job.update_columns(ready_to_invoice_notified_at: nil) if job.ready_to_invoice_notified_at
  end

  # Several visits for one job at once (multi-day work: one visit per date), under one lock on
  # the job; the people going hear about them in one notification each.
  def self.schedule_all!(visits, by:, notify_client: true)
    job = visits.first.job
    job.with_lock do
      raise NotOpen, "#{job.number} is #{job.status_label.downcase}. Reopen it to change its visits." unless job.open?

      visits.each do |visit|
        visit.save!
        visit.sync_assignments
        VisitEvent.record!(visit, :scheduled, by:, to: visit.snapshot, crew: visit.crew_names, crew_ids: visit.assignees.map(&:id))
        ClientEvent.record!(job.client, :visit_scheduled, subject: visit, by:, when: visit.when_label(with_year: true)) # CLI-05
      end
      visits.first.reset_ready_to_invoice
      job.refresh_status!
      visits.first.tell_client(notify_client, visits, by:)
    end
    crew = visits.flat_map { _1.assignees.to_a }.uniq
    dates = visits.size == 1 ? visits.first.when_label : "#{visits.size} days (#{visits.map { _1.scheduled_on.strftime("%b %-d") }.to_sentence}), #{visits.first.time_label}"
    visits.first.notify_crew("visit_assigned", crew, "You're on #{job.title} (#{job.number}): #{dates}", by:)
    visits
  end

  # The days to book from the form: the first day, then every day through a last day (skipping
  # days the business is closed, if asked) and other days picked one by one. Stops one past
  # MAX_DAYS (so "too many" can be reported) however far away the last day is. Raises
  # BadDates for a last day before the first.
  def self.plan_dates(first, through: nil, extra: [], skip_closed: false, hours: nil)
    first = parse_date(first) or return []
    last = parse_date(through)
    raise BadDates, "The last day is before the first." if last && last < first

    dates = [ first ]
    day = first + 1
    while last && day <= last && dates.size <= MAX_DAYS
      dates << day unless skip_closed && hours && !hours.open_on?(day)
      day += 1
    end
    dates += Array(extra).first(MAX_DAYS + 1).filter_map { parse_date(_1) }
    dates.uniq.sort.first(MAX_DAYS + 1)
  end

  # Only YYYY-MM-DD, as date fields send (Date.parse would read "Nov" as Nov 1).
  def self.parse_date(value) = (Date.iso8601(value.to_s) if value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)) rescue nil

  # Date, time, duration, crew or instructions changed; records what changed and who changed it.
  # A change to the crew alone still changes the visit's row, so lock_version catches a stale form.
  def reschedule!(attributes, by:, notify_client: true)
    under_job_lock do
      lock!
      raise NotOpen, "This visit is #{status_label.downcase}." unless open?

      before, before_crew, before_duration = snapshot, assignees.to_a, duration_minutes
      assign_attributes(attributes)
      crew_changed = !@assignee_ids.nil? && @assignee_ids.sort != before_crew.map(&:id).sort
      self.updated_at = Time.current if crew_changed && !changed?
      details = (changes.keys & %w[duration_minutes instructions])
      save!
      sync_assignments
      after_crew = assignees.reload.to_a
      moved = snapshot.except("when") != before.except("when")
      VisitEvent.record!(self, :rescheduled, by:, from: before, to: snapshot) if moved
      tell_client(notify_client, by:) if moved
      update_columns(reminder_sent_at: nil) if reminder_sent_at && before["on"] != scheduled_on.iso8601 # a new day gets its own reminder
      added, removed = after_crew - before_crew, before_crew - after_crew
      if added.any? || removed.any?
        VisitEvent.record!(self, :reassigned, by:, added: added.map(&:full_name), removed: removed.map(&:full_name),
                                               added_ids: added.map(&:id), removed_ids: removed.map(&:id))
      end
      VisitEvent.record!(self, :updated, by:, changed: details, duration_from: before_duration, duration_to: duration_minutes) if details.any?

      notify_crew("visit_assigned", added, "You're on #{job.title} (#{job.number}): #{when_label}", by:)
      notify_crew("visit_changed", removed, "You're no longer on #{job.title} (#{job.number}) on #{before["when"].sub(/, #{business.today.year} ·/, " ·")}", by:,
                  path: Rails.application.routes.url_helpers.admin_my_day_path) # the visit isn't theirs to open any more
      if moved || details.any?
        what = details.map { { "duration_minutes" => "duration", "instructions" => "instructions" }.fetch(_1) }.to_sentence
        title = moved ? "Moved: #{job.title} (#{job.number}) is now #{when_label}" : "New #{what}: #{job.title} (#{job.number}), #{when_label}"
        notify_crew("visit_changed", after_crew - added, title, by:, body: (instructions if details.include?("instructions")))
      end
    end
  end

  # Cancelling the last open visit of a job whose other visits were done also means it's ready
  # to invoice.
  def cancel!(by:, reason: nil, notify_client: true)
    under_job_lock do
      lock!
      finish!("cancelled", by:, reason:)
      notify_ready_to_invoice(by:) if !job.visits.open.exists? && job.visits.where(status: "completed").exists?
      tell_client(notify_client, by:)
    end
  end

  def restore!(by:, notify_client: true)
    under_job_lock do
      lock!
      raise NotOpen, "This visit isn't cancelled." unless status == "cancelled"

      update!(status: "scheduled", cancelled_at: nil, cancel_reason: nil)
      VisitEvent.record!(self, :restored, by:)
      reset_ready_to_invoice
      update_columns(reminder_sent_at: nil)
      tell_client(notify_client, by:)
      notify_crew("visit_assigned", assignees.to_a, "Back on: #{job.title} (#{job.number}), #{when_label}", by:)
    end
  end

  # Adds one photo from site (SitePhotos). Returns an error sentence, or nil.
  def add_photo(file, by:) = add_site_photo(photos, file, by:, max: MAX_PHOTOS, max_bytes: PHOTO_MAX_BYTES,
                                                              full: "This visit already has the most photos it can (#{MAX_PHOTOS}).")

  # On site (JOB-04): the person going starts the visit.
  def start!(by:)
    under_job_lock do
      lock!
      raise NotOpen, "This visit is #{status_label.downcase}." unless status == "scheduled"

      update!(status: "in_progress", started_at: Time.current)
      VisitEvent.record!(self, :started, by:)
    end
  end

  # Done (staff from the job page; the people going from their day view, JOB-04). Completing a
  # job's last open visit tells the office it's ready to invoice.
  def complete!(by:)
    under_job_lock do
      lock!
      finish!("completed", by:)
      notify_ready_to_invoice(by:) unless job.visits.open.exists?
    end
  end

  # A visit completed by mistake can be reopened the same day (by the business's clock).
  def reopenable? = status == "completed" && job.open? && completed_at && completed_at.in_time_zone(place.time_zone).to_date == place.today

  def reopen!(by:)
    under_job_lock do
      lock!
      raise NotOpen, "Only a visit completed today can be reopened." unless reopenable?

      update!(status: started_at ? "in_progress" : "scheduled", completed_at: nil)
      VisitEvent.record!(self, :reopened, by:)
      ClientEvent.record!(job.client, :visit_reopened, subject: self, by:) # CLI-05
      reset_ready_to_invoice
    end
  end

  # Ends an open visit as completed or cancelled. Callers hold the job's and the visit's locks
  # (Job#complete! and #cancel! lock their open visits up front, and tell the crew once
  # themselves rather than per visit).
  def finish!(status, by:, reason: nil, notify: true)
    raise NotOpen, "This visit is already #{status_label.downcase}." unless open?

    if status == "completed"
      update!(status:, completed_at: Time.current)
      VisitEvent.record!(self, :completed, by:)
      ClientEvent.record!(job.client, :visit_completed, subject: self, by:) # CLI-05
    else
      update!(status:, cancelled_at: Time.current, cancel_reason: reason)
      VisitEvent.record!(self, :cancelled, by:, reason: cancel_reason)
      ClientEvent.record!(job.client, :visit_cancelled, subject: self, by:, when: when_label(with_year: true)) # CLI-05
      notify_crew("visit_cancelled", assignees.to_a, "Cancelled: #{job.title} (#{job.number}), #{when_label}", by:, body: cancel_reason) if notify
    end
  end

  # NTF-02: tells the people going (not whoever made the change). The notification opens the
  # job for those who can see jobs, and the visit in their day view (JOB-04) for everyone else.
  def notify_crew(kind, users, title, by:, body: nil, path: nil)
    users = Array(users).reject { _1.id == by&.id }
    return if users.empty?

    paths = Rails.application.routes.url_helpers
    office = business.business_users.active.where(user: users).select { _1.can?(:office) }.map(&:user_id)
    users.partition { office.include?(_1.id) }.zip([ paths.admin_job_path(job), path || paths.admin_my_visit_path(self) ]).each do |group, path|
      NotificationType.deliver(kind, business:, subject: self, actor: by, to: group, title:, body:, path:) if group.any?
    end
  end

  # JOB-04: the office hears that a job's visits are all done, once until a visit opens again.
  def notify_ready_to_invoice(by:)
    return if job.ready_to_invoice_notified_at

    job.update_columns(ready_to_invoice_notified_at: Time.current)
    NotificationType.deliver("job_ready_to_invoice", business:, subject: job, actor: by,
                             title: "#{job.title} (#{job.number}) is ready to invoice", body: "#{by&.full_name || "The crew"} completed the last visit.",
                             path: Rails.application.routes.url_helpers.admin_job_path(job))
  end

  # JOB-05: what the client would be told about this visit: booked (and when) or cancelled.
  def client_state
    { "state" => status == "cancelled" ? "cancelled" : "booked", "when" => when_label, "on" => scheduled_on.iso8601,
      "timing" => timing, "starts_at" => starts_at&.utc&.iso8601, "window_ends_at" => window_ends_at&.utc&.iso8601 }
  end

  # Whether the client has been told about the visit as it is now ("when" is only the label).
  def client_up_to_date? = client_told&.except("when", "emailed_at") == client_state.except("when")

  # What the client would be told about it now: "scheduled", "changed", "cancelled", or nil when
  # they already know (a change undone, or a cancelled visit they never heard of).
  def client_change_kind
    told = client_told
    if status == "cancelled" then "cancelled" if told&.dig("state") == "booked"
    elsif told.nil? || told["state"] == "cancelled" then "scheduled"
    elsif !client_up_to_date? then "changed"
    end
  end

  # After a change the client should hear about: their email goes out shortly, with the job's
  # other changes. When staff chose not to tell them (or can't email clients yet, ACC-01, or the
  # client has no email), this is what the client knows, unless an email about an earlier change
  # is already on its way: then that email carries the visit as it is now, rather than the
  # earlier change being lost.
  def tell_client(notify_client, visits = [ self ], by: nil)
    sender_ok = by.nil? || by.can_send_to_clients?
    # #289: only queue an email the business sends (its visit emails can be off, kind by kind).
    wanted = visits.any? { (kind = _1.client_change_kind) && business.client_visit_email?(kind) }
    if notify_client && sender_ok && job.client.primary_email && wanted
      job.queue_client_notice!
    elsif job.client_notice_due_at.nil?
      visits.each { _1.update_columns(client_told: _1.client_state) }
    end
  end

  # The client's page for this visit (PLT-12): one link per visit, kept alive until a month
  # after the visit's day, wherever it moves.
  def client_link!
    expires_at = business.local_time(scheduled_on + 30, "23:59")
    link = ClientLink.active.where(linkable: self).order(:id).last
    return ClientLink.issue!(self, expires_at:) unless link

    link.update!(expires_at:) if link.expires_at && link.expires_at < expires_at
    link
  end

  def client_page_visible? = true
  def client_link_partial = "client/visits/visit"

  def crew_names = assignees.map(&:full_name)

  # Called by schedule_all! for each visit it saves.
  def sync_assignments
    return if @assignee_ids.nil?

    current = assignments.map(&:user_id)
    assignments.where(user_id: current - @assignee_ids).delete_all
    (@assignee_ids - current).each { assignments.create!(user_id: _1) }
    assignments.reset
    assignees.reset
    @assignee_ids = nil
  end

  private

  # Every change takes the job's lock, then the visit's (the order Job#complete! uses, so the two
  # can't deadlock), checks the job is still open, and saves the change, its history and the
  # job's status together.
  def under_job_lock
    job.with_lock do
      raise NotOpen, "#{job.number} is #{job.status_label.downcase}. Reopen it to change its visits." unless job.open?

      yield
      job.refresh_status!
    end
    self
  end

  # CAT-07: visits keep the time of their job's location (its zone; the business's for the main
  # one). With one location there's nothing to look up.
  def place
    return business if business.nil? || !business.multiple_locations?

    location = Tenancy.with_business(business) { job&.location }
    location.nil? || location.primary? ? business : location
  end

  # Active members, or someone already on this visit (kept even after they're deactivated).
  def assignees_are_members
    return if @assignee_ids.nil? || @assignee_ids.empty?

    allowed = business.business_users.active.where(user_id: @assignee_ids).pluck(:user_id) + (persisted? ? assignments.pluck(:user_id) : [])
    errors.add(:base, "Only people on your team can be assigned.") unless (@assignee_ids - allowed).empty?
  end
end
