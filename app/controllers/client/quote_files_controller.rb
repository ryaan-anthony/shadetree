# A quote's photos and files on the client page (QTE-03), served through the link so that
# revoking or expiring it also cuts off the files: each request is checked, then redirected
# to a short-lived storage URL.
class Client::QuoteFilesController < ApplicationController
  include ClientLinkAccess
  include ActiveStorage::SetCurrent

  URL_LIFETIME = 5.minutes

  def show
    return render_link_not_found unless @document.is_a?(Quote) && @document.client_visible?

    attachment = @document.attachments_attachments.find_by(id: params[:id]) or return render_link_not_found
    file = params[:size] == "web" && attachment.image? ? attachment.variant(:web).processed : attachment
    # The browser may reuse the redirect while the storage URL it points to is still valid, so
    # revisiting the page doesn't download every photo again.
    expires_in URL_LIFETIME - 1.minute, public: false
    redirect_to file.url(expires_in: URL_LIFETIME, disposition: :inline), allow_other_host: true
  end
end
