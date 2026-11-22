# CLI-07: who follows up a request, how (a site visit or a call) and when: a day, and a start
# time, an arrival window or anytime that day (ArrivalTiming, as visits are), with a duration
# and instructions for them. A request has at most one, changed in place by RequestFollowUp.assign!
# while the request is New or In progress, and removed when it's unassigned, quoted or archived.
# Each change is in the request's history (ServiceRequestEvent) and tells the people concerned
# (NTF-02).
class RequestFollowUp < ApplicationRecord
  include BusinessOwned
  include ArrivalTiming

  KINDS = %w[visit call].freeze
  KIND_LABELS = { "visit" => "Site visit", "call" => "Call" }.freeze
  # With no duration given: a site visit takes about an hour, a call a quarter of one.
  DEFAULT_MINUTES = { "visit" => 60, "call" => 15 }.freeze

  class NotOpen < StandardError; end

  belongs_to_business_record :service_request
  belongs_to :user, optional: true # the assignee (assignee_is_member says when there is none)
  belongs_to :assigned_by, class_name: "User", optional: true
  belongs_to :done_by, class_name: "User", optional: true # JOB-06

  normalizes :instructions, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :instructions, length: { maximum: 2_000 }
  validate :assignee_is_member

  before_validation :default_duration
  # The form's field is the duration in hours, so its error goes there (with the field's own wiring).
  after_validation { errors.add(:duration_hours, "Give a duration between 5 minutes and 24 hours.") if errors.delete(:duration_minutes).present? }

  delegate :client, :location, to: :service_request

  # Whether this change gives a duration (default_duration leaves a given one alone).
  def duration_minutes=(value)
    @duration_given = !value.nil?
    super
  end

  def kind_label = KIND_LABELS.fetch(kind)
  def visit? = kind == "visit"

  # "site visit for Maria Lopez", "call with Maria Lopez"
  def summary = visit? ? "site visit for #{client.display_name}" : "call with #{client.display_name}"

  # JOB-02's warnings ask everything booked who's on it.
  def assignee_ids = [ user_id ].compact

  # The day it's on has passed and it's still to do.
  def overdue? = !done? && scheduled_on < place.today

  # JOB-06: the assignee has done the visit or made the call. It stays theirs until they create
  # the quote or pass the request back (or the office moves it on).
  def done? = done_at.present?

  # Assigns `request` (to someone new, or the same person at another time, or with other
  # details): attributes are the form's (user, kind, scheduled_on, timing, start_time,
  # window_end_time, duration_hours, instructions, lock_version). A New request moves to In
  # progress. Raises NotOpen once the request is quoted or archived, ActiveRecord::RecordInvalid
  # and ActiveRecord::StaleObjectError as saving does.
  # `fresh: true` (a form that showed no follow-up) refuses one someone else assigned meanwhile.
  def self.assign!(request, attributes, by:, fresh: false)
    request.with_lock do
      raise NotOpen, "This request is #{request.status_label.downcase}, so it can't be assigned." unless request.open?
      raise ActiveRecord::StaleObjectError.new(request.follow_up, "assign") if fresh && request.follow_up

      follow_up = request.follow_up || request.build_follow_up(business: request.business)
      before, before_user = (follow_up.state if follow_up.persisted?), (follow_up.user if follow_up.persisted?)
      follow_up.assign_attributes(attributes)
      follow_up.assigned_by = by if follow_up.new_record? || follow_up.user_id_changed?
      follow_up.validate # works out the times, so a change of who, day or time can be seen
      # JOB-06: given to someone else, or moved, it's to do again; other details leave it done.
      follow_up.done_at = follow_up.done_by = nil if (follow_up.changes.keys & %w[user_id scheduled_on timing starts_at window_ends_at]).any?
      follow_up.save!
      request.update!(status: "in_progress") if request.status == "new"
      follow_up.record_change(before, before_user, by:)
      follow_up
    end
  end

  # Why a follow-up ended, for the assignee's notice ("left_team" needs none: they've gone).
  ENDINGS = { "quoted" => "A quote was made from the request.", "archived" => "The request was archived.",
              "role_changed" => "Your role changed, so it's back with the office." }.freeze

  # Taken off the assignee: unassigned by staff, or (`reason`, ENDINGS) the request was quoted
  # or archived, the assignee left the team, or their role changed. Callers hold the request's lock.
  def end!(by:, reason: nil)
    before = state
    destroy!
    ServiceRequestEvent.record!(service_request, reason ? :ended : :unassigned, by:, from: before, reason:)
    notify("request_changed", user, "No longer yours: #{summary}, #{when_label}", by:, body: ENDINGS[reason])
  end

  # Who can follow requests up (JOB-06): any role that works from My day (field_work) or the
  # request page (office).
  def self.assignable?(membership) = membership.active? && (membership.can?(:office) || membership.can?(:field_work))

  # Someone deactivated, removed from the business, deleting their account or given a role that
  # can't follow requests up: their follow-ups end (in each request's history), and the requests
  # go back to New for someone to pick up.
  def self.release!(user, business, by: Current.user, reason: "left_team")
    Tenancy.with_business(business) do
      RequestFollowUp.where(user_id: user.id).includes(:service_request).find_each do |follow_up|
        request = follow_up.service_request
        request.with_lock do
          request.follow_up&.end!(by:, reason:)
          request.update!(status: "new") if request.status == "in_progress"
        end
      end
    end
  end

  # What it is now, for the history: who, how, when (Visit#snapshot's keys) and for how long.
  def state = snapshot.merge("user_id" => user_id, "kind" => kind, "duration_minutes" => duration_minutes)

  # JOB-06: the assignee marks it done; whoever assigned it hears (NTF-02). The request stays In
  # progress. Raises NotOpen if it's already done, or the request has been closed meanwhile.
  def done!(by:)
    service_request.with_lock do
      reload
      raise NotOpen, "This is already marked done." if done?
      raise NotOpen, "This request is #{service_request.status_label.downcase}." unless service_request.open?

      update!(done_at: Time.current, done_by: by)
      ServiceRequestEvent.record!(service_request, :done, by:, from: state)
      if (to = told_when_done(by))
        NotificationType.deliver("request_follow_up_done", business:, subject: service_request, actor: by, to: [ to ],
                                 title: "#{by&.full_name || "Someone"} did the #{summary}", body: "Ready for a quote, or for what comes next.",
                                 path: Rails.application.routes.url_helpers.admin_service_request_path(service_request))
      end
    end
    self
  end

  # JOB-06: hands the request back to whoever assigned it, for today, anytime, with what the
  # assignee found as an internal note. Raises NotOpen when there's nobody to pass it back to.
  # Only the assignee, once it's done, and only while it's still theirs (checked under the
  # request's lock, so the office moving it meanwhile wins). Their instructions go with it.
  def pass_back!(by:, note: nil)
    request = service_request
    request.with_lock do
      reload
      raise NotOpen, "This isn't yours to pass back any more." unless user_id == by&.id
      raise NotOpen, "Mark it done first." unless done?
      raise NotOpen, "There's nobody to pass this back to. Ask the office to reassign it." unless (to = pass_back_to)

      request.notes.create!(business:, user: by, body: note) if note.present?
      request.passing_back = note.to_s # record_change tells it apart from a reassignment
      self.class.assign!(request, { user: to, scheduled_on: request.location&.today || business.today, timing: "anytime", instructions: nil }, by:)
    ensure
      request.passing_back = nil
    end
  end

  # Who it'd go back to: whoever assigned it, if they're still on the team in a role that can
  # take it, and isn't the assignee. Nil means the office has to reassign it.
  def pass_back_to
    return if assigned_by.nil? || assigned_by_id == user_id

    member = business.business_users.active.find_by(user_id: assigned_by_id)
    assigned_by if member && self.class.assignable?(member)
  end

  # Who hears that it's done (NTF-02's "A follow-up you gave is done" needs request access):
  # whoever assigned it, unless that's who did it or they've left.
  def told_when_done(by)
    return if assigned_by.nil? || assigned_by_id == by&.id

    assigned_by if business.business_users.active.find_by(user_id: assigned_by_id)&.can?(:office)
  end

  # The history lines and notices for what assign! just changed from `before` (nil when new).
  def record_change(before, before_user, by:)
    after = state
    record_booking(by:) if visit?
    return assigned(after, by:) if before.nil?

    moved = after.slice("on", "timing", "starts_at", "window_ends_at") != before.slice("on", "timing", "starts_at", "window_ends_at")
    details = %w[kind duration_minutes instructions].select { _1 == "instructions" ? saved_change_to_instructions? : before[_1] != after[_1] }
    passed_back = before["user_id"] != user_id && by&.id == before["user_id"] && service_request.passing_back
    ServiceRequestEvent.record!(service_request, passed_back ? :passed_back : :reassigned, by:, from_user_id: before["user_id"], to_user_id: user_id) if before["user_id"] != user_id
    ServiceRequestEvent.record!(service_request, :rescheduled, by:, from: before, to: after) if moved && !passed_back # passing back sets today, anytime
    ServiceRequestEvent.record!(service_request, :updated, by:, changed: details, from: before, to: after) if details.any? && !passed_back

    if passed_back
      notify("request_assigned", user, "Passed back to you: #{summary}", by:, body: service_request.passing_back.presence)
    elsif before_user && before_user.id != user_id
      notify("request_changed", before_user, "No longer yours: #{summary}, #{before["when"].sub(/, #{business.today.year} ·/, " ·")}", by:,
             body: "It's been given to someone else on the team.") # no name, so ACC-06 has none to scrub
      notify("request_assigned", user, "Yours to follow up: #{summary}, #{when_label}", by:, body: instructions)
    elsif moved || details.any?
      notify("request_changed", user, moved ? "Moved: #{summary} is now #{when_label}" : "Changed: #{summary}, #{when_label}", by:,
             body: (instructions if details.include?("instructions")))
    end
  end

  # NTF-02: tells the person concerned (not whoever did it). The notice opens the follow-up on
  # their day (JOB-06) for those who work from My day, else the request; once it's no longer
  # theirs, My day or the request page.
  def notify(kind, person, title, by:, body: nil)
    return if person.nil? || person.id == by&.id

    paths = Rails.application.routes.url_helpers
    member = business.business_users.active.find_by(user: person)
    theirs = person.id == user_id && !destroyed?
    path = if theirs then paths.admin_my_request_path(service_request)
    elsif member&.can?(:field_work) then paths.admin_my_day_path
    else paths.admin_service_request_path(service_request)
    end
    NotificationType.deliver(kind, business:, subject: service_request, actor: by, to: [ person ], title:, body:, path:)
  end

  private

  # CLI-05: one "Site visit booked" line per follow-up on the client's timeline, saying the day
  # it's booked for now (moved, or a call made a site visit again, it's updated, not repeated).
  def record_booking(by:)
    line = ClientEvent.where(client_id: service_request.client_id, kind: "follow_up_booked").where("data ->> 'follow_up' = ?", uid).first
    data = { "when" => when_label(with_year: true), "follow_up" => uid }
    return ClientEvent.record!(client, :follow_up_booked, subject: service_request, by:, **data) unless line

    ClientEvent.where(id: line.id).update_all(data: line.data.merge(data)) if line.data["when"] != data["when"]
  end

  # With no duration given, the kind's usual one. When the kind changes and no duration is
  # given with it, a duration that was the old kind's usual one becomes the new kind's.
  def default_duration
    usual = DEFAULT_MINUTES[kind]
    if duration_minutes.nil?
      self.duration_minutes = usual
    elsif kind_changed? && kind_was && !@duration_given && duration_minutes == DEFAULT_MINUTES[kind_was]
      self.duration_minutes = usual
    end
  end

  def assigned(after, by:)
    ServiceRequestEvent.record!(service_request, :assigned, by:, to: after)
    notify("request_assigned", user, "Yours to follow up: #{summary}, #{when_label}", by:, body: instructions)
  end

  # CAT-07: the request's location's clock (its zone; the business's for the main one).
  def place
    return business if business.nil? || !business.multiple_locations?

    location = Tenancy.with_business(business) { service_request&.location }
    location.nil? || location.primary? ? business : location
  end

  # Anyone active on the team who can see requests (office). JOB-06 opens this to every role,
  # once follow-ups show on My day.
  def assignee_is_member
    return errors.add(:user_id, "Choose who follows it up.") if user.nil?

    member = business.business_users.active.find_by(user_id:)
    errors.add(:user_id, "Only people on your team whose role has My day or requests can be assigned.") unless member && self.class.assignable?(member)
  end
end
