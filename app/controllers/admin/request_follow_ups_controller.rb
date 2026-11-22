# CLI-07: assigning a request to someone to follow up (a site visit or a call, on a day, at a
# time or anytime), moving it, handing it on, or unassigning it. Office work, like the inbox.
# Warnings (hours, closures, the person already booked) come back to the form first, as for
# visits; "Assign anyway" goes ahead.
class Admin::RequestFollowUpsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include FollowUpForm
  requires_permission :office
  before_action :set_request
  before_action :require_open_request, only: %i[edit update]

  def edit
    @follow_up = @request.follow_up || start_follow_up(@request)
  end

  def update
    raise ActiveRecord::StaleObjectError.new(@request.follow_up, "assign") if fresh? && @request.follow_up

    @follow_up = @request.follow_up || @request.build_follow_up
    @follow_up.assign_attributes(follow_up_params)
    return render(:edit, status: :unprocessable_content) unless @follow_up.valid?
    return render(:edit, status: :unprocessable_content) if follow_up_warn?(@follow_up)

    follow_up = RequestFollowUp.assign!(@request, follow_up_params, by: current_user, fresh: fresh?)
    redirect_to admin_service_request_path(@request), notice: "#{follow_up.user.full_name} has it: #{follow_up.kind_label.downcase}, #{follow_up.when_label}."
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
    case outcome
    when :none then redirect_to admin_service_request_path(@request), notice: "Nobody had it."
    when :stale then redirect_to admin_service_request_path(@request), alert: "Someone else changed this follow-up meanwhile. Here's the latest."
    else redirect_to admin_service_request_path(@request), notice: "Unassigned. Nobody's following this request up."
    end
  end

  private

  # The form showed no follow-up, so one assigned since then isn't overwritten.
  def fresh? = params[:fresh] == "1"

  def follow_up_params = @follow_up_params ||= follow_up_attributes(params.expect(request_follow_up: FollowUpForm::FIELDS))

  def set_request = @request = ServiceRequest.includes(:client, :location).find_by_param!(params[:service_request_id])

  def require_open_request
    redirect_to admin_service_request_path(@request), alert: "This request is #{@request.status_label.downcase}. Mark it in progress to assign it." unless @request.open?
  end
end
