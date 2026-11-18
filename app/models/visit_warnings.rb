# JOB-02: what's worth a second look before booking or moving visits: a time outside the
# business's hours, a day it's closed, a closure (CAT-06), or someone going who's already on
# another visit then. Warnings never stop the booking; staff can schedule anyway.
#
#   VisitWarnings.for([ visit ])   # => ["Marcus Reyes is on J-0003 Gutter cleaning then (9–11 am)."]
#
# A visit's time for these checks runs from its start to its end (a window's latest arrival plus
# the duration). "Anytime" visits are checked against the day only, and don't overlap anything.
class VisitWarnings
  def self.for(visits, hours: nil) = new(visits, hours:).messages

  def initialize(visits, hours: nil)
    @visits = Array(visits)
    @business = @visits.first&.business
    @hours = hours
  end

  def messages
    return [] if @visits.empty?

    hours = @hours || OpeningHours.new(@business)
    several = @visits.size > 1
    @visits.flat_map do |visit|
      found = hours.problems(visit.scheduled_on, visit.starts_at, visit.ends_at).map(&:message) + overlaps(visit)
      several ? found.map { "#{visit.scheduled_on.strftime("%a, %b %-d")}: #{_1}" } : found
    end.uniq
  end

  private

  # Visits on the same date only: a visit running past midnight from the day before isn't seen.
  def overlaps(visit)
    return [] if visit.anytime? || visit.assignee_ids.empty?

    others.select { |other| other.scheduled_on == visit.scheduled_on && other.id != visit.id && !other.anytime? &&
                            other.starts_at < visit.ends_at && visit.starts_at < other.ends_at }
          .flat_map { |other| (other.assignees.map(&:id) & visit.assignee_ids).map { [ other, _1 ] } }
          .map { |other, user_id| "#{people[user_id]} is on #{other.job.number} #{other.job.title} then (#{other.time_label.delete_prefix("Arrive ")})." }
  end

  # Open visits on the same days for anyone going, in one query.
  def others
    @others ||= begin
      ids = @visits.flat_map(&:assignee_ids).uniq
      ids.empty? ? [] : Visit.open.where(scheduled_on: @visits.map(&:scheduled_on).uniq).joins(:assignments)
                             .where(visit_assignments: { user_id: ids }).distinct.includes(:job, :assignees).to_a
    end
  end

  def people = @people ||= User.where(id: @visits.flat_map(&:assignee_ids)).to_h { [ _1.id, _1.full_name ] }
end
