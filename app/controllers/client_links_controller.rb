# The page a client lands on from a link: /c/:token (PLT-12).
class ClientLinksController < ApplicationController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only
  include ClientLinkAccess
  skip_before_action :load_client_link, only: :request_fresh
  before_action :load_link_for_request, only: :request_fresh

  def show
    # A document that isn't meant for clients yet (a draft quote) is never shown (QTE-03).
    visible = @document.respond_to?(:client_page_visible?) ? @document.client_page_visible? : @document.try(:client_visible?) != false
    return render_link_unavailable unless visible

    # A page saying the quote is being revised isn't a view of the quote.
    # Nor is support viewing the app as a member (OPS-03).
    @client_link.record_view!(device: client_device) unless @document.try(:revising?) || impersonation
  end

  # From the "no longer active" page: tell the business the client wants a new link.
  def request_fresh
    @client_link.request_fresh_link!(device: client_device) unless @client_link.fresh_link_requested_at&.after?(1.hour.ago)
    @requested = true
    render "client_links/unavailable", status: :ok
  end

  private

  def load_link_for_request
    @client_link = ClientLink.find_by_token(params[:token])
    return render_link_not_found unless @client_link

    @business = @client_link.business
    Current.business = @business
  end
end
