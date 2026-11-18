# CLI-03: tells an office team member a request came in from the public form, with everything
# they need to call back. Sent through NotificationType.deliver (NTF-02), to the members who
# want it.
class NewRequestMailer < TeamMailer
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
