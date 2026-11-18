# JOB-04: photos on one of the signed-in member's visits. The day view sends one photo per
# request, with progress and a retry on a dropped connection, and gets the new thumbnail back;
# without scripts, the plain form sends several and comes back to the visit.
class Admin::MyVisitPhotosController < Admin::BaseController
  requires_permission :field_work
  before_action :set_visit

  def create
    files = Array(params[:photos]).compact_blank.first(Visit::MAX_PHOTOS)
    return respond_with_error("Choose a photo first.") if files.empty?

    errors = files.filter_map { @visit.add_photo(_1, by: current_user) }
    if request.format.html? && !request.xhr?
      redirect_to admin_my_visit_path(@visit, anchor: "photos"), **(errors.any? ? { alert: errors.to_sentence } : { notice: "#{helpers.pluralize(files.size - errors.size, "photo")} added." })
    elsif errors.any?
      respond_with_error(errors.first)
    else
      render partial: "admin/my_visits/photo", locals: { photo: @visit.photos.reload.last, visit: @visit, number: @visit.photos.size }, status: :created
    end
  end

  # Someone going can take a photo back off (a wrong one, a duplicate).
  def destroy
    photo = @visit.photos.find(params[:id])
    photo.purge_later
    redirect_to admin_my_visit_path(@visit, anchor: "photos"), notice: "Photo removed."
  end

  private

  def set_visit
    @visit = Visit.joins(:assignments).where(visit_assignments: { user_id: current_user.id }).find_by_param!(params[:my_visit_id])
  end

  def respond_with_error(message)
    if request.format.html? && !request.xhr?
      redirect_to admin_my_visit_path(@visit, anchor: "photos"), alert: message
    else
      render plain: message, status: :unprocessable_content
    end
  end
end
