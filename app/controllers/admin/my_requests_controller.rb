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

  # QTE-07: the quote, pre-filled as from the inbox (CLI-04), by someone who can quote the
  # requests given to them (or office staff following one up). The request becomes Quoted and
  # the follow-up ends; the draft stays theirs to edit until it's sent.
  def quote
    return deny!(:quote_requests, "can't quote requests") unless can?(:office) || can?(:quote_requests)
    return redirect_to(admin_my_request_path(@request), alert: "Mark it done first.") unless @follow_up.done?
    return redirect_to(admin_my_request_path(@request), alert: "#{@request.client.display_name} is archived. Ask the office to restore them.") if @request.client.archived?

    quote = @request.create_quote!(by: current_user)
    redirect_to edit_admin_quote_path(quote), notice: "Draft #{quote.number} from the request. Nothing is sent until #{can?(:send_own_quotes) ? "you send it" : "the office sends it"}."
  end

  def pass_back
    to = @follow_up.pass_back_to
    @follow_up.pass_back!(by: current_user, note: params[:note].to_s.strip.first(5_000))
    redirect_to (can?(:field_work) ? admin_my_day_path : admin_service_requests_path), notice: "Passed back to #{to&.full_name}."
  rescue RequestFollowUp::NotOpen, ActiveRecord::RecordInvalid => error
    redirect_to admin_my_request_path(@request), alert: error.message.delete_prefix("Validation failed: ")
  end
end
