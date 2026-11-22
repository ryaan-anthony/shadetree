# JOB-06: an internal note on a request the signed-in member is following up (what they found).
class Admin::MyRequestNotesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include MyRequestAccess

  def create
    note = @request.notes.build(business: current_business, user: current_user, body: params.dig(:service_request_note, :body))
    if note.save
      redirect_to admin_my_request_path(@request, anchor: "notes"), notice: "Note added."
    else
      redirect_to admin_my_request_path(@request, anchor: "notes"), alert: note.errors.full_messages.to_sentence
    end
  end
end
