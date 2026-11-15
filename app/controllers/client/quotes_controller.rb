# What a client can do with a quote through its link (QTE-03; approve/decline come in QTE-05).
class Client::QuotesController < ApplicationController
  include ClientLinkAccess

  before_action :require_quote

  # An expired quote: the client asks the business for an updated one. Recorded once an
  # hour at most; staff see it on the quote (QTE-06 adds the team notification).
  def request_update
    unless @document.update_requested_at&.after?(1.hour.ago) || !@document.expired?
      @document.update!(update_requested_at: Time.current)
      @client_link.events.create!(business: @business, kind: "quote_update_requested", device: client_device, occurred_at: Time.current)
    end
    redirect_to client_link_path(@client_link.token), notice: "Thanks. #{@business.name} has been asked for an updated quote."
  end

  private

  def require_quote
    render_link_not_found unless @document.is_a?(Quote) && @document.client_visible?
  end
end
