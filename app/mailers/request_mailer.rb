# CLI-03: the acknowledgment a person gets after sending the request form. It repeats nothing
# they typed (only the business's own service names and the timing they picked), so the form
# can't be used to put someone else's words in an email to an address they choose.
class RequestMailer < ClientMailer
  def received
    @request = ServiceRequest.find(params[:request_id])
    client_mail subject: "#{@business.name} received your request"
  end
end
