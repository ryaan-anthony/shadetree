# CLI-07: assigning a request to someone to follow up (a site visit or a call, on a day, at a
# time or anytime), moving it, handing it on, or unassigning it. Office work, like the inbox.
# Warnings (hours, closures, the person already booked) come back to the form first, as for
# visits; "Assign anyway" goes ahead.
class Admin::RequestFollowUpsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include FollowUpForm
  include GridClock # JOB-07: a slot's time is on the calendar's clock
  requires_permission :office
  before_action :set_request
  before_action :require_open_request, only: %i[edit update]

  def edit
    @follow_up = @request.follow_up || start_follow_up(@request)
    prefill_from_schedule
  end

  def update
    raise ActiveRecord::StaleObjectError.new(@request.follow_up, "assign") if fresh? && @request.follow_up

    @follow_up = @request.follow_up || @request.build_follow_up
    @follow_up.assign_attributes(follow_up_params)
    return render(:edit, status: :unprocessable_content) unless @follow_up.valid?
    return render(:edit, status: :unprocessable_content) if follow_up_warn?(@follow_up)

    follow_up = RequestFollowUp.assign!(@request, follow_up_params, by: current_user, fresh: fresh?)
    back = from_schedule? ? back_to_schedule(date: follow_up.scheduled_on, focus: @request.uid) : admin_service_request_path(@request)
    redirect_to back, notice: "#{follow_up.user.full_name} has it: #{follow_up.kind_label.downcase}, #{follow_up.when_label}."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_content
  rescue ActiveRecord::StaleObjectError
    redirect_to edit_admin_service_request_follow_up_path(@request), alert: "Someone else assigned or changed this follow-up meanwhile. Here's the latest."
  rescue RequestFollowUp::NotOpen => error
    redirect_to admin_service_request_path(@request), alert: error.message
  end

  # The page sends the follow-up's lock_version, so a stale page can't take off someone it
  # didn't show (or a follow-up changed since).
  def destroy
    outcome = @request.with_lock do
      follow_up = @request.reload.follow_up
      next :none unless follow_up
      next :stale if params[:lock_version].present? && params[:lock_version].to_i != follow_up.lock_version

      follow_up.end!(by: current_user)
      :done
    end
    # JOB-07: unassigned from the calendar, back to it as it was
    back = params[:from] == "schedule" ? admin_schedule_path(params.permit(:date, :view, :member).to_h.compact_blank) : admin_service_request_path(@request)
    case outcome
    when :none then redirect_to back, notice: "Nobody had it."
    when :stale then redirect_to back, alert: "Someone else changed this follow-up meanwhile. Here's the latest."
    else redirect_to back, notice: "Unassigned. Nobody's following this request up."
    end
  end

  private

  # JOB-07: booked from a slot on the calendar (?from=schedule): the slot's day and start (on
  # the calendar's clock, ?grid_zone=, as the request's location keeps its own) and its person;
  # afterwards, back to the calendar as it was (Admin::VisitsController's calendar params).
  def prefill_from_schedule
    return unless from_schedule?

    on = Visit.parse_date(params[:on])
    at = params[:at].to_s[/\A(?:[01]\d|2[0-3]):[0-5]\d\z/]
    on, at = from_grid_clock(on, at, to: @follow_up.time_zone) if on
    @follow_up.scheduled_on = on if on
    @follow_up.assign_attributes(timing: "exact", start_time: at) if at
    member = current_business.business_users.active.find_by(user_id: params[:crew].to_i) if params[:crew].to_s.match?(/\A\d+\z/)
    @follow_up.user = member.user if member && RequestFollowUp.assignable?(member)
  end

  helper_method def from_schedule? = params[:from] == "schedule"
  helper_method def calendar_params = Admin::ScheduleController.calendar_params(params)

  helper_method def back_to_schedule(date:, focus: nil)
    calendar = calendar_params
    admin_schedule_path({ date: date&.iso8601, view: calendar[:view], member: calendar[:member], focus: focus || calendar[:slot] }.compact_blank)
  end

  # The form showed no follow-up, so one assigned since then isn't overwritten.
  def fresh? = params[:fresh] == "1"

  def follow_up_params = @follow_up_params ||= follow_up_attributes(params.expect(request_follow_up: FollowUpForm::FIELDS))

  def set_request = @request = ServiceRequest.includes(:client, :location).find_by_param!(params[:service_request_id])

  def require_open_request
    redirect_to admin_service_request_path(@request), alert: "This request is #{@request.status_label.downcase}. Mark it in progress to assign it." unless @request.open?
  end
end
