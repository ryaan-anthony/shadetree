# CLI-03: tells the office team a request came in from the public form, with everything they
# need to call back.
class NewRequestMailer < TeamMailer
  def self.deliver_later_for(request)
    office_members(request.business).each do |user|
      with(business_id: request.business_id, request_id: request.id, user_id: user.id).received.deliver_later
    end
  end

  def received
    @business = Business.find(params[:business_id])
    user = User.find(params[:user_id])
    Tenancy.with_business(@business) do
      @request = ServiceRequest.includes(:client, :property).find(params[:request_id])
      @url = admin_client_url(@request.client)
    end
    mail to: user.email, subject: "New request from #{@request.contact_name}"
  end
end
