# ACC-09: a team member's photo on a client's visit page, served through the visit's link as
# quote and invoice files are (Client::DocumentFilesController): checked on every request, so
# revoking or expiring the link, turning team profiles off or deactivating the member cuts it
# off, then redirected to a storage URL that expires in 5 minutes. Only someone a card or
# message about this visit shows (Visit#client_team_shown): assigned to it, active, with a first
# name, while the business shows team profiles.
class Client::TeamPhotosController < ApplicationController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only
  include ClientLinkAccess
  include ActiveStorage::SetCurrent

  URL_LIFETIME = Client::DocumentFilesController::URL_LIFETIME

  def show
    return render_link_not_found unless @document.is_a?(Visit)

    member = @document.client_team_shown.find { _1.uid == params[:id].to_s }
    return render_link_not_found unless member&.photo&.attached?

    expires_in URL_LIFETIME - 1.minute, public: false
    redirect_to member.photo.variant(:card).processed.url(expires_in: URL_LIFETIME, disposition: :inline), allow_other_host: true
  end
end
