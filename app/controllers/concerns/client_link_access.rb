# For every client-facing controller reached through a secure link (PLT-12, ADR 0016).
# Resolves the link from params[:token], refuses anything not active with a friendly page,
# then acts as the link's business for the rest of the request.
#
#   class Client::QuotesController < ApplicationController
#     include ClientLinkAccess
#     def approve
#       if client_link_action!(:approve) { @document.approve! }
#         redirect_to client_link_path(@client_link.token), notice: "Quote approved."
#       else
#         redirect_to client_link_path(@client_link.token), alert: "This quote was already answered."
#       end
#     end
#   end
module ClientLinkAccess
  extend ActiveSupport::Concern

  included do
    layout "client"
    # Order matters: rate limit and headers apply even when the link is unknown or inactive.
    rate_limit to: 120, within: 1.minute, by: -> { request.remote_ip }, with: -> { too_many_requests }
    before_action :set_client_page_headers
    before_action :load_client_link
  end

  private

  def set_client_page_headers
    response.set_header("X-Robots-Tag", "noindex, nofollow")
    # Keep tokens out of the Referer other sites see. Not "no-referrer": with it, browsers send
    # "Origin: null" when the page's own forms submit natively (not through Turbo's fetch), and
    # Rails' CSRF origin check refuses them.
    response.set_header("Referrer-Policy", "same-origin")
  end

  def load_client_link
    @client_link = ClientLink.find_by_token(params[:token])
    return render_link_not_found unless @client_link

    @business = @client_link.business
    Current.business = @business
    @document = Tenancy.across_businesses(reason: "client link document") { @client_link.linkable }
    render_link_unavailable unless @client_link.usable?
  end

  # Runs a one-time action (approve, pay) at most once, only if this link allows it.
  def client_link_action!(action, &)
    @client_link.perform_once!(action, device: client_device, &)
  end

  def client_device = ClientDevice.describe(request.user_agent)

  def render_link_not_found
    render "client_links/not_found", status: :not_found
  end

  def render_link_unavailable
    render "client_links/unavailable", status: :gone
  end
end
