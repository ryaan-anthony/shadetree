# JOB-06: photos the signed-in member takes on a request they're following up, as on a visit
# (JOB-04): the day view sends one at a time with progress and retry and gets the thumbnail
# back; without scripts, the plain form sends several and comes back to the page.
class Admin::MyRequestPhotosController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include MyRequestAccess

  def create
    files = Array(params[:photos]).compact_blank.first(Visit::MAX_PHOTOS)
    return respond_with_error("Choose a photo first.") if files.empty?

    errors = files.filter_map { @request.add_site_photo_from(_1, by: current_user) }
    if request.format.html? && !request.xhr?
      redirect_to admin_my_request_path(@request, anchor: "photos"), **(errors.any? ? { alert: errors.to_sentence } : { notice: "#{helpers.pluralize(files.size - errors.size, "photo")} added." })
    elsif errors.any?
      respond_with_error(errors.first)
    else
      render partial: "admin/my_requests/photo", locals: { photo: @request.site_photos.reload.order(:id).last, request_record: @request, number: @request.site_photos.size }, status: :created
    end
  end

  # The person following it up can take a photo they took back off (a wrong one, a duplicate);
  # one an earlier assignee took is the record of their visit, so it's "not found".
  def destroy
    photo = @request.site_photos.find(params[:id])
    raise ActiveRecord::RecordNotFound unless photo.metadata["uploaded_by"] == current_user.id

    photo.purge_later
    redirect_to admin_my_request_path(@request, anchor: "photos"), notice: "Photo removed."
  end

  private

  def respond_with_error(message)
    if request.format.html? && !request.xhr?
      redirect_to admin_my_request_path(@request, anchor: "photos"), alert: message
    else
      render plain: message, status: :unprocessable_content
    end
  end
end
