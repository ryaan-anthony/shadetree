# JOB-04: a note on one of the signed-in member's visits.
class Admin::MyVisitNotesController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :field_work

  def create
    visit = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id }).find_by_param!(params[:my_visit_id])
    note = visit.notes.new(body: params.dig(:visit_note, :body), user: current_user)
    if note.save
      redirect_to admin_my_visit_path(visit, anchor: "notes"), notice: "Note added."
    else
      redirect_to admin_my_visit_path(visit, anchor: "notes"), alert: note.errors.full_messages.to_sentence
    end
  end
end
