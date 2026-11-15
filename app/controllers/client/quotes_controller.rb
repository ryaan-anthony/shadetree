# What a client can do with a quote through its link (QTE-03; approve/decline come in QTE-05).
class Client::QuotesController < ApplicationController
  include ClientLinkAccess
  include SendsPdf

  before_action :require_quote

  # An expired quote: the client asks the business for an updated one. Recorded once per
  # quote (a repeat, a double tap or a second device changes nothing); the revision the
  # business sends next (QTE-06) is the answer. Staff see it in the quotes list.
  def request_update
    return redirect_to(client_link_path(@client_link.token)) unless @document.expired?

    if record_update_request
      redirect_to client_link_path(@client_link.token), notice: "Thanks. #{@business.name} has been asked for an updated quote."
    else
      redirect_to client_link_path(@client_link.token), notice: "You've already asked. #{@business.name} will send an updated quote."
    end
  end

  # QTE-02: the quote as a PDF, to print, forward or file.
  def pdf = send_pdf(@document, back: client_link_path(@client_link.token))

  private

  def require_quote
    render_link_not_found unless @document.is_a?(Quote) && @document.client_visible?
  end

  # A conditional update, so concurrent requests record it once. The SQL-string form, because
  # the hash form bumps lock_version and would interrupt a staff member editing the quote.
  def record_update_request
    Quote.transaction do
      now = Time.current
      next false unless Quote.where(id: @document.id, update_requested_at: nil).update_all([ "update_requested_at = ?", now ]) == 1

      @client_link.events.create!(business: @business, kind: "quote_update_requested", device: client_device, occurred_at: now)
      true
    end
  end
end
