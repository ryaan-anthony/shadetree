# CLI-04: internal notes on a request.
class Admin::ServiceRequestNotesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office

  def create
    request = ServiceRequest.find_by_param!(params[:service_request_id])
    note = request.notes.build(business: current_business, user: current_user, body: params.dig(:service_request_note, :body))
    if note.save
      redirect_to admin_service_request_path(request, anchor: "notes"), notice: "Note added."
    else
      redirect_to admin_service_request_path(request, anchor: "notes"), alert: "Write something before adding the note."
    end
  end
end
