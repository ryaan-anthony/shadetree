# JOB-06: the request the signed-in member is following up (its follow-up is theirs), for their
# day's pages. Anyone who can work from My day (field_work); anything else is "not found".
module MyRequestAccess
  extend ActiveSupport::Concern

  included do
    requires_permission :field_work
    before_action :set_my_request
  end

  private

  def set_my_request
    id = params[:my_request_id] || params[:id]
    @request = ServiceRequest.joins(:follow_up).where(request_follow_ups: { user_id: current_user.id })
                             .includes(:client, :property, :location, follow_up: %i[assigned_by], notes: :user).find_by_param!(id)
    @follow_up = @request.follow_up
  end
end
