# OPS-05: a screenshot on a support ticket, for operators: checked, then redirected to a
# short-lived storage URL (the page never links to a permanent one).
class Ops::TicketFilesController < Ops::BaseController
  include ActiveStorage::SetCurrent

  def show
    ticket = Tenancy.across_businesses(reason: Ops::TicketsController::REASON) { SupportTicket.find_by!(uid: params[:ticket_id].to_s) }
    file = Tenancy.with_business(ticket.business) do
      ActiveStorage::Attachment.where(record_type: "SupportMessage", name: "files", record_id: ticket.messages.select(:id)).find_by!(id: params[:id])
    end
    expires_in Admin::SupportTicketFilesController::URL_LIFETIME - 1.minute, public: false
    redirect_to file.url(expires_in: Admin::SupportTicketFilesController::URL_LIFETIME, disposition: :inline), allow_other_host: true
  end
end
