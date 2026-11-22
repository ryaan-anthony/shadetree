# JOB-06: a request the signed-in member is following up, from their day: who and where, what
# was asked for, the office's notes, and Done; then create the quote (if their role allows) or
# pass it back. Only while it's theirs: any other request is "not found".
class Admin::MyRequestsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include MyRequestAccess

  def show
    @note = ServiceRequestNote.new
  end

  def done
    @follow_up.done!(by: current_user)
    told = @follow_up.told_when_done(current_user)
    redirect_to admin_my_request_path(@request), notice: "Done.#{" #{told.full_name} knows." if told}"
  rescue RequestFollowUp::NotOpen => error
    redirect_to admin_my_request_path(@request), alert: error.message
  end

  def pass_back
    to = @follow_up.pass_back_to
    @follow_up.pass_back!(by: current_user, note: params[:note].to_s.strip.first(5_000))
    redirect_to (can?(:field_work) ? admin_my_day_path : admin_service_requests_path), notice: "Passed back to #{to&.full_name}."
  rescue RequestFollowUp::NotOpen, ActiveRecord::RecordInvalid => error
    redirect_to admin_my_request_path(@request), alert: error.message.delete_prefix("Validation failed: ")
  end
end
