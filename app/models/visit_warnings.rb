# JOB-02: what's worth a second look before booking or moving visits: a time outside the
# location's hours (CAT-07), a day it's closed, a closure (CAT-06), or someone going who's already on
# another visit then. Warnings never stop the booking; staff can schedule anyway.
#
#   VisitWarnings.for([ visit ])   # => ["Marcus Reyes is on J-0003 Gutter cleaning then (9–11 am)."]
#
# A visit's time for these checks runs from its start to its end (a window's latest arrival plus
# the duration). "Anytime" visits are checked against the day only, and don't overlap anything.
#
# CLI-07: request follow-ups (RequestFollowUp) are checked the same way, against their request's
# location, and visits and follow-ups warn about each other.
class VisitWarnings
  def self.for(visits, hours: nil) = new(visits, hours:).messages

  def initialize(visits, hours: nil)
    @visits = Array(visits)
    @business = @visits.first&.business
    @hours = hours
  end

  def messages
    return [] if @visits.empty?

    several = @visits.size > 1
    @visits.flat_map do |visit|
      found = hours_for(visit).problems(visit.scheduled_on, visit.starts_at, visit.ends_at).map(&:message) + overlaps(visit)
      several ? found.map { "#{visit.scheduled_on.strftime("%a, %b %-d")}: #{_1}" } : found
    end.uniq
  end

  private

  # CAT-07: each visit is checked against its job's location's hours, closures and zone (a
  # follow-up against its request's).
  def hours_for(item)
    return @hours if @hours

    owner = item.is_a?(Visit) ? item.job : item.service_request
    (@by_location ||= {})[owner.location_id] ||= owner.location.then { OpeningHours.new(_1.nil? || _1.primary? ? item.business : _1) }
  end

  # Visits on the same date only: a visit running past midnight from the day before isn't seen.
  def overlaps(visit)
    return [] if visit.anytime? || visit.assignee_ids.empty?

    others.select { |other| other.scheduled_on == visit.scheduled_on && !(other.class == visit.class && other.id == visit.id) && !other.anytime? &&
                            other.starts_at < visit.ends_at && visit.starts_at < other.ends_at }
          .flat_map { |other| (other.assignee_ids & visit.assignee_ids).map { [ other, _1 ] } }
          .map { |other, user_id| "#{people[user_id]} #{busy_with(other)} then (#{other.time_label.delete_prefix("Arrive ")})." }
  end

  def busy_with(other) = other.is_a?(Visit) ? "is on #{other.job.number} #{other.job.title}" : "has a #{other.summary}"

  # Open visits and request follow-ups on the same days for anyone going, in one query each.
  def others
    @others ||= begin
      ids = @visits.flat_map(&:assignee_ids).uniq
      days = @visits.map(&:scheduled_on).uniq
      return @others = [] if ids.empty?

      found = Visit.open.where(scheduled_on: days).joins(:assignments).where(visit_assignments: { user_id: ids }).distinct.includes(job: :location, assignments: []).to_a +
              RequestFollowUp.where(scheduled_on: days, user_id: ids).includes(service_request: %i[client location]).to_a
      found.each { _1.association(:business).target = @business } # one business (and its location count) for all of them, not one each
    end
  end

  def people = @people ||= User.where(id: @visits.flat_map(&:assignee_ids)).to_h { [ _1.id, _1.full_name ] }
end
