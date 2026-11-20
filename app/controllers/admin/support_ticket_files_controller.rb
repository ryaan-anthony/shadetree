# OPS-05: a screenshot on a support ticket, for members of the ticket's business. Checked on
# every request, then redirected to a short-lived storage URL, so the link in the page isn't a
# permanent public one. Internal notes never have files a member can reach.
class Admin::SupportTicketFilesController < Admin::BaseController
  impersonation :blocked # OPS-03: downloads are off while viewing as a member (the console has its own)
  include ActiveStorage::SetCurrent

  URL_LIFETIME = 5.minutes

  allow_any_member

  def show
    ticket = SupportTicket.visible_to(current_membership).find_by_param!(params[:support_ticket_id])
    file = ActiveStorage::Attachment.where(record_type: "SupportMessage", name: "files",
                                           record_id: ticket.messages.where(internal: false).select(:id)).find_by!(id: params[:id])
    expires_in URL_LIFETIME - 1.minute, public: false
    redirect_to file.url(expires_in: URL_LIFETIME, disposition: :inline), allow_other_host: true
  end
end
