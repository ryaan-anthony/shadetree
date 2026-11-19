# What a client can do with an invoice through its link (PAY-02): download it. Paying online
# comes with PAY-04.
class Client::InvoicesController < ApplicationController
  include ClientLinkAccess
  include SendsPdf

  before_action :require_invoice

  def pdf
    # While a corrected revision is being prepared there's no finished document to download.
    return redirect_to(client_link_path(@client_link.token)) unless @document.client_visible?

    send_pdf(@document, back: client_link_path(@client_link.token))
  end

  private

  def require_invoice
    render_link_not_found unless @document.is_a?(Invoice) && @document.client_page_visible?
  end
end
