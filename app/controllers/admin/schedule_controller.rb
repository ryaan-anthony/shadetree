# JOB-03: the team calendar (Owners and Admins; technicians use My day). A week or a day of
# visits on a time grid, or an agenda list on phones, filtered by member; the jobs still
# needing a visit beside it. Opening a visit shows it in a side panel.
class Admin::ScheduleController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :schedule
  filters_by_location Visit, Job, only: %i[show new_visit] # CAT-07
  # The visit panel loads into its frame in the background; a load finishing after an Undo
  # click mustn't overwrite that click's flash. (The full page, on phones, writes as usual.)
  leaves_session_alone only: :visit, if: -> { turbo_frame_request? }

  NEW_VISIT_JOBS = 200 # the open jobs a new visit can be for; past that, schedule it from the job

  def show
    date = Visit.parse_date(params[:date])
    member = params[:member].presence
    member = nil unless member == "unassigned" || current_business.business_users.active.exists?(user_id: member.to_i)
    @schedule = ScheduleView.new(current_business, view: params[:view], date:, member: member && (member == "unassigned" ? member : member.to_i),
                                                   color_by: params[:color], location: location_filter)
  end

  # A visit dragged to another day, time or person (JOB-03), or changed in the quick-edit sheet.
  # Same warnings as the visit form: the first answer lists them, and the same move sent again
  # with their digest goes ahead. An undo (from the toast) skips them. On success the next page
  # shows a toast with Undo; drags get JSON and reload the calendar themselves.
  def move
    @visit = Visit.includes(:assignees, job: %i[client property]).find_by_param!(params[:id])
    previous = { on: @visit.scheduled_on.iso8601, at: @visit.start_time, crew: @visit.assignee_ids.map(&:to_s).presence || [ "" ] } # [""]: nobody, kept through compact_blank
    return refuse("Someone changed this visit just now. Here's the latest.", status: :conflict) if params[:lock_version].to_s != @visit.lock_version.to_s

    on = Date.iso8601(params[:on].to_s) rescue nil
    return refuse("Choose a day.") unless on

    on, at = from_grid_clock(on, params[:at].presence)
    changes = @visit.move_attributes(on:, at:, from: member_param(:from), to: member_param(:to),
                                     crew: (Array(params[:crew]).select { _1.is_a?(String) || _1.is_a?(Integer) }.map(&:to_s).compact_blank if params.key?(:crew)))
    @visit.assign_attributes(changes)
    return refuse(@visit.errors.full_messages.to_sentence) unless @visit.valid?
    return render_move(:ok, "Nothing changed.") unless @visit.when_or_crew_changed?

    @warnings = VisitWarnings.for([ @visit ])
    # An undo puts back what was there, so it doesn't warn again. (Warnings are advice, not rules:
    # anyone who can move a visit can also choose "Move anyway".)
    if @warnings.any? && params[:undo].blank? && params[:confirm] != Admin::VisitsController.digest(@warnings)
      respond_to do |format|
        format.json { render json: { warnings: @warnings, confirm: Admin::VisitsController.digest(@warnings) }, status: :unprocessable_content }
        format.html do
          @proposed = { on: @visit.scheduled_on, at: @visit.start_time, crew: @visit.assignee_ids }
          @visit = Visit.includes(:assignees, job: %i[client property]).find(@visit.id) # the details show it as it is; the sheet, as asked
          render :visit, status: :unprocessable_content
        end
      end
      return
    end

    @visit.reload.reschedule!(changes.merge(lock_version: params[:lock_version]), by: current_user) # stale since the check above: refused
    flash[:notice] = "#{params[:undo].present? ? "Put back" : "Moved"}: #{@visit.job.client.display_name}, #{@visit.when_label}#{" · #{@visit.crew_names.to_sentence.presence || "nobody yet"}" if changes.key?(:assignee_ids)}."
    flash[:undo] = { "path" => admin_schedule_move_path(@visit), "params" => previous.merge(lock_version: @visit.lock_version, undo: 1, view: params[:view], member: params[:member]).compact_blank } unless params[:undo].present?
    render_move(:ok)
  rescue ArgumentError => error
    refuse(error.message)
  rescue ActiveRecord::StaleObjectError
    refuse("Someone changed this visit just now. Here's the latest.", status: :conflict)
  rescue Visit::NotOpen => error
    refuse(error.message)
  end

  # QA #274 (WCAG 2.1.1): a slot on the grid, or "New visit", asks which job the visit is for
  # (beside the calendar, or on its own page), then opens that job's new-visit form with the
  # day, time and person filled in. The slot's time is on the calendar's clock (CAT-07).
  def new_visit
    @on = [ Visit.parse_date(params[:on]), grid_place.today ].compact.max
    @at = params[:at].to_s[/\A(?:[01]\d|2[0-3]):[0-5]\d\z/]
    @member = current_business.business_users.active.includes(:user).find_by(user_id: params[:member].to_i)&.user if params[:member].to_s.match?(/\A\d+\z/)
    return redirect_to(new_job_visit_path(Job.find_by_param!(params[:job]))) if params[:job].present?

    @jobs = Job.unfinished.includes(:client, :property).order(Arel.sql("CASE WHEN jobs.status = 'unscheduled' THEN 0 ELSE 1 END"), :created_at, :id).limit(NEW_VISIT_JOBS).to_a
    render partial: "admin/schedule/new_visit", layout: false if turbo_frame_request?
  end

  # The details of one visit, for the panel beside the calendar.
  def visit
    @visit = Visit.includes(:assignees, job: %i[client property]).find_by_param!(params[:id])
    render partial: "admin/schedule/visit", locals: { visit: @visit }, layout: false if turbo_frame_request?
  end

  private

  # The new-visit form for a job, at the slot's day and time on the job's own clock, with the
  # slot's person, and back to the calendar afterwards.
  def new_job_visit_path(job)
    on, at = shift_clock(@on, @at, from: grid_place.time_zone, to: job.location.time_zone)
    new_admin_job_visit_path(job, { on: on.iso8601, at:, member: @member&.id, from: "schedule", view: params[:view] }.compact_blank)
  end

  def grid_place = location_filter || current_business

  # CAT-07: a drag's day and time are on the calendar's clock (?grid_zone=); a visit keeps its
  # location's, so a visit in another zone gets the same moment on its own clock.
  def from_grid_clock(on, at)
    zone = ActiveSupport::TimeZone[params[:grid_zone].to_s] if params[:grid_zone].present?
    zone ? shift_clock(on, at, from: zone, to: @visit.time_zone) : [ on, at ]
  end

  # A day and "HH:MM" on one clock, as the same moment on another.
  def shift_clock(on, at, from:, to:)
    return [ on, at ] unless at.to_s.match?(/\A\d\d:\d\d/) && from.tzinfo.identifier != to.tzinfo.identifier

    hour, minute = at.to_s.split(":").map { Integer(_1, 10) }
    local = from.local(on.year, on.month, on.day, hour, minute).in_time_zone(to)
    [ local.to_date, local.strftime("%H:%M") ]
  end

  # A member id from the drag ("none" for the "Nobody yet" column), only if they're in this business.
  def member_param(key)
    value = params[key].presence
    return nil if value.nil? || value == "none"

    current_business.business_users.where(user_id: value.to_i).pick(:user_id) || raise(ArgumentError, "That person isn't on your team.")
  end

  # Focus goes back to the visit that was moved (QA #274; schedule_focus_controller).
  def back_to_calendar = admin_schedule_path({ view: params[:view], date: (@visit&.scheduled_on || current_business.today).iso8601, member: params[:member], focus: @visit&.uid }.compact_blank)

  def render_move(status, message = nil)
    flash[:notice] = message if message
    respond_to do |format|
      format.json { render json: { ok: true }, status: }
      format.html { redirect_to back_to_calendar }
    end
  end

  def refuse(message, status: :unprocessable_content)
    flash[:alert] = message
    respond_to do |format|
      format.json { render json: { error: message }, status: }
      format.html { redirect_to back_to_calendar }
    end
  end
end
