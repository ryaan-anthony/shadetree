# What a client can do with a quote through its link: download it and ask for an update to an
# expired one (QTE-03), and approve, decline or ask for changes (QTE-05).
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

  # QTE-05. Approving signs with a typed name and agreement to the terms, against the version
  # of the quote the page showed.
  def approve
    # A typed email only counts when there's none on file (the form only offers it then).
    keys = @document.client.primary_email ? %i[signer_name terms_accepted] : %i[signer_name email terms_accepted]
    respond_to_quote(:approve, response_params(*keys), version: params[:version].presence || -1)
  end

  def decline = respond_to_quote(:decline, response_params(:message))
  def request_changes = respond_to_quote(:request_changes, response_params(:message))

  # QTE-02: the quote as a PDF, to print, forward or file.
  def pdf = send_pdf(@document, back: client_link_path(@client_link.token))

  private

  RESPONDED = {
    approve: nil, # the page's own banner thanks them
    decline: ->(business, _) { "#{business.name} has been told you declined the quote." },
    request_changes: ->(business, _) { "Sent. #{business.name} will update the quote and send you a new version." }
  }.freeze

  # Records the response once (a double tap or a second device gets "already answered"),
  # with the evidence: the link, IP address, browser and device.
  def respond_to_quote(action, attributes, version: nil)
    @response_action = action
    unless @client_link.actions.include?(action.to_s)
      return redirect_to(client_link_path(@client_link.token), alert: "This link can't be used to answer the quote. Ask #{@business.name} for a new one.")
    end

    attributes = attributes.merge(ip_address: request.remote_ip, user_agent: request.user_agent.to_s.first(500).presence, device: client_device)
    record = -> { @response = @document.record_response!(action, link: @client_link, version:, **attributes) }
    recorded = if ClientLink::ONE_TIME_ACTIONS.include?(action.to_s)
      client_link_action!(action, &record)
    else
      # Not one-time per link, but still refused once the quote is answered, and re-checked
      # under a lock so a revoke that just committed wins.
      ClientLink.transaction { @client_link.lock!.allows?(action) && record.call }
    end
    return redirect_to(client_link_path(@client_link.token), notice: RESPONDED.fetch(action)&.call(@business, @response)) if recorded
    # The link stopped working while this request waited for it (revoked, expired).
    return render_link_unavailable unless @client_link.reload.usable?

    redirect_to client_link_path(@client_link.token), alert: "This quote has already been answered."
  rescue ActiveRecord::RecordInvalid => error
    @response = error.record
    render "client_links/show", status: :unprocessable_content
  rescue Quote::Changed
    redirect_to client_link_path(@client_link.token), alert: "This quote was updated after you opened it. Check this version, then approve again."
  rescue Quote::NotOpen
    expired = action == :approve ? "This quote has expired, so it can't be approved as is." : "This quote has expired. Ask for an updated one below."
    redirect_to client_link_path(@client_link.token), alert: @document.reload.expired? ? expired : "This quote has already been answered."
  end

  def response_params(*keys) = params.fetch(:quote_response, {}).permit(*keys).to_h.symbolize_keys

  def require_quote
    render_link_not_found unless @document.is_a?(Quote) && @document.client_visible?
  end

  # A conditional update, so concurrent requests record it once. The SQL-string form, because
  # the hash form bumps lock_version and would interrupt a staff member editing the quote.
  def record_update_request
    Quote.transaction do
      # Re-read the link under a lock, so a revoke committed after this request loaded it wins
      # (as ClientLink#perform_once! does).
      @client_link.lock!
      next false unless @client_link.usable?

      now = Time.current
      next false unless Quote.where(id: @document.id, update_requested_at: nil).update_all([ "update_requested_at = ?", now ]) == 1

      @client_link.events.create!(business: @business, kind: "quote_update_requested", device: client_device, occurred_at: now)
      true
    end
  end
end
