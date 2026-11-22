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

  normalizes :instructions, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :instructions, length: { maximum: 2_000 }
  validate :assignee_is_member

  before_validation :default_duration

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
  def overdue? = scheduled_on < place.today

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
      follow_up.save!
      request.update!(status: "in_progress") if request.status == "new"
      follow_up.record_change(before, before_user, by:)
      follow_up
    end
  end

  # Why a follow-up ended, for the assignee's notice ("left_team" needs none: they've gone).
  ENDINGS = { "quoted" => "A quote was made from the request.", "archived" => "The request was archived." }.freeze

  # Taken off the assignee: unassigned by staff, or (`reason`, ENDINGS) the request was quoted
  # or archived, or the assignee left the team. Callers hold the request's lock.
  def end!(by:, reason: nil)
    before = state
    destroy!
    ServiceRequestEvent.record!(service_request, reason ? :ended : :unassigned, by:, from: before, reason:)
    notify("request_changed", user, "No longer yours: #{summary}, #{when_label}", by:, body: ENDINGS[reason])
  end

  # Someone deactivated, removed from the business or deleting their account: their follow-ups
  # end (in each request's history), and the requests go back to New for someone to pick up.
  def self.release!(user, business, by: Current.user)
    Tenancy.with_business(business) do
      RequestFollowUp.where(user_id: user.id).includes(:service_request).find_each do |follow_up|
        request = follow_up.service_request
        request.with_lock do
          request.follow_up&.end!(by:, reason: "left_team")
          request.update!(status: "new") if request.status == "in_progress"
        end
      end
    end
  end

  # What it is now, for the history: who, how, when (Visit#snapshot's keys) and for how long.
  def state = snapshot.merge("user_id" => user_id, "kind" => kind, "duration_minutes" => duration_minutes)

  # The history lines and notices for what assign! just changed from `before` (nil when new).
  def record_change(before, before_user, by:)
    after = state
    record_booking(by:) if visit?
    return assigned(after, by:) if before.nil?

    moved = after.slice("on", "timing", "starts_at", "window_ends_at") != before.slice("on", "timing", "starts_at", "window_ends_at")
    details = %w[kind duration_minutes instructions].select { _1 == "instructions" ? saved_change_to_instructions? : before[_1] != after[_1] }
    ServiceRequestEvent.record!(service_request, :reassigned, by:, from_user_id: before["user_id"], to_user_id: user_id) if before["user_id"] != user_id
    ServiceRequestEvent.record!(service_request, :rescheduled, by:, from: before, to: after) if moved
    ServiceRequestEvent.record!(service_request, :updated, by:, changed: details, from: before, to: after) if details.any?

    if before_user && before_user.id != user_id
      notify("request_changed", before_user, "No longer yours: #{summary}, #{before["when"].sub(/, #{business.today.year} ·/, " ·")}", by:,
             body: "It's been given to someone else on the team.") # no name, so ACC-06 has none to scrub
      notify("request_assigned", user, "Yours to follow up: #{summary}, #{when_label}", by:, body: instructions)
    elsif moved || details.any?
      notify("request_changed", user, moved ? "Moved: #{summary} is now #{when_label}" : "Changed: #{summary}, #{when_label}", by:,
             body: (instructions if details.include?("instructions")))
    end
  end

  # NTF-02: tells the person concerned (not whoever did it). The notice opens the request for
  # those who can see requests, and their day for everyone else (JOB-06 shows it there).
  def notify(kind, person, title, by:, body: nil)
    return if person.nil? || person.id == by&.id

    paths = Rails.application.routes.url_helpers
    office = business.business_users.active.find_by(user: person)&.can?(:office)
    NotificationType.deliver(kind, business:, subject: service_request, actor: by, to: [ person ], title:, body:,
                                   path: office ? paths.admin_service_request_path(service_request) : paths.admin_my_day_path)
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
    errors.add(:user_id, "Only people on your team who can see requests can be assigned.") unless member&.can?(:office)
  end
end
