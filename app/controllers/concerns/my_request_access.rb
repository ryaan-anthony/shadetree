# JOB-06: the request the signed-in member is following up (its follow-up is theirs, and it's
# open), for their day's pages. Anyone who can be assigned (My day or the request page); any
# other request is "not found".
module MyRequestAccess
  extend ActiveSupport::Concern

  included do
    allow_any_member
    before_action { deny!(:field_work, "no My day or requests") unless can?(:field_work) || can?(:office) }
    before_action :set_my_request
  end

  private

  def set_my_request
    id = params[:my_request_id] || params[:id]
    @request = ServiceRequest.where(status: ServiceRequest::OPEN_STATUSES).joins(:follow_up).where(request_follow_ups: { user_id: current_user.id })
                             .includes(:client, :property, :location, follow_up: %i[assigned_by], notes: :user).find_by_param!(id)
    @follow_up = @request.follow_up
  end
end
