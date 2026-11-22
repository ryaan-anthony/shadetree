# JOB-07: a request follow-up opened or moved on the team calendar, for people who can manage
# requests (CLI-07). Moving works as for visits (JOB-03): a drag or the quick-edit sheet gives
# the day, the start (on the calendar's clock) and the person; warnings come first, then "Move
# anyway"; the toast after a move offers Undo. Assigning, notices and history are CLI-07's.
class Admin::ScheduleFollowUpsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include GridClock # CAT-07
  requires_permission :office
  # The panel loads into its frame in the background; it mustn't take an Undo's flash (as visits').
  leaves_session_alone only: :show, if: -> { turbo_frame_request? }
  before_action :set_follow_up, except: :new

  # From a slot: the chosen request's assign form, with the slot's day, time and person.
  def new
    request = ServiceRequest.where(status: ServiceRequest::OPEN_STATUSES).find_by_param!(params[:request])
    redirect_to edit_admin_service_request_follow_up_path(request, params.permit(:on, :at, :crew, :grid_zone, *Admin::ScheduleController::CALENDAR_PARAMS.keys).merge(from: "schedule"))
  end

  def show
    render partial: "admin/schedule/follow_up_panel", locals: { follow_up: @follow_up }, layout: false if turbo_frame_request?
  end

  def move
    previous = { on: @follow_up.scheduled_on.iso8601, at: @follow_up.start_time, to: @follow_up.user_id.to_s }
    return refuse("Someone changed this follow-up just now. Here's the latest.", status: :conflict) if params[:lock_version].to_s != @follow_up.lock_version.to_s

    on = Date.iso8601(params[:on].to_s) rescue nil
    return refuse("Choose a day.") unless on

    return refuse("This follow-up is done. Move it from the request if it needs doing again.") if @follow_up.done?

    on, at = from_grid_clock(on, params[:at].presence, to: @follow_up.time_zone)
    changes = { scheduled_on: on, **@follow_up.moved_time_attributes(at) }
    if (to = person_param)
      changes[:user] = to
    end
    @follow_up.assign_attributes(changes)
    return refuse(@follow_up.errors.full_messages.to_sentence) unless @follow_up.valid?
    return render_move("Nothing changed.") if (@follow_up.changes.keys & %w[user_id scheduled_on timing starts_at window_ends_at]).empty?

    @warnings = VisitWarnings.for([ @follow_up ])
    if @warnings.any? && params[:undo].blank? && params[:confirm] != Admin::VisitsController.digest(@warnings)
      respond_to do |format|
        format.json { render json: { warnings: @warnings, confirm: Admin::VisitsController.digest(@warnings) }, status: :unprocessable_content }
        format.html do
          @proposed = { on: @follow_up.scheduled_on, at: @follow_up.start_time, user_id: @follow_up.user_id }
          set_follow_up # the details show it as it is; the sheet, as asked
          render :show, status: :unprocessable_content
        end
      end
      return
    end

    moved = RequestFollowUp.assign!(@request, changes.merge(lock_version: params[:lock_version]), by: current_user)
    flash[:notice] = "#{params[:undo].present? ? "Put back" : "Moved"}: #{moved.summary.upcase_first}, #{moved.when_label} · #{moved.user.full_name}."
    unless params[:undo].present?
      flash[:undo] = { "path" => admin_schedule_follow_up_move_path(@request), "params" => previous.merge(lock_version: moved.lock_version, undo: 1, view: params[:view], member: params[:member]).compact_blank }
    end
    @follow_up = moved
    render_move
  rescue ArgumentError => error
    refuse(error.message)
  rescue ActiveRecord::StaleObjectError
    refuse("Someone changed this follow-up just now. Here's the latest.", status: :conflict)
  rescue ActiveRecord::RecordInvalid, RequestFollowUp::NotOpen => error
    refuse(error.message.delete_prefix("Validation failed: "))
  end

  private

  def set_follow_up
    @request = ServiceRequest.includes(:client, :property, :location, follow_up: :user).find_by_param!(params[:id])
    @follow_up = @request.follow_up or raise ActiveRecord::RecordNotFound
  end

  # The person: from a drag between columns (?from=, ?to=), or the sheet's choice (?to=). Only
  # someone on this team; validation decides whether they can take it.
  def person_param
    value = params[:to].to_s
    return if value.blank? || value == params[:from].to_s
    raise ArgumentError, "A follow-up needs someone. Use Unassign instead." if value == "none"

    current_business.business_users.active.find_by(user_id: value.to_i)&.user || raise(ArgumentError, "That person isn't on your team.")
  end

  # Focus goes back to the follow-up that was moved (schedule_focus_controller).
  def back_to_calendar
    admin_schedule_path({ view: params[:view], date: (@follow_up&.scheduled_on || current_business.today).iso8601, member: params[:member], focus: @request&.uid }.compact_blank)
  end

  def render_move(message = nil)
    flash[:notice] = message if message
    respond_to do |format|
      format.json { render json: { ok: true } }
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
