# Sending a quote (QTE-04): by email (the branded email with a "View quote" button and the PDF
# attached), or by getting the link to send from the owner's own phone. The first send of
# either kind marks the quote sent and counts toward plan usage (BIL-02); resends don't.
class Admin::QuoteSendsController < Admin::BaseController
  include ConfirmedSender

  requires_permission :office
  before_action :set_quote
  before_action :require_sendable
  before_action :require_confirmed_sender, only: :create

  def new
    @form = QuoteSendForm.new(to: @quote.client.primary_email&.value, subject: QuoteMailer.default_subject(@quote),
                              message: default_message)
    @link = ClientLink.active.where(linkable: @quote).order(created_at: :desc).first unless @quote.draft?
  end

  def create
    params[:channel] == "link" ? send_link : send_email
  end

  private

  def set_quote = @quote = Quote.includes(:client, :line_items).find_by_param!(params[:quote_id])

  def require_sendable
    return if @quote.sendable?

    message = @quote.line_items.empty? ? "Add at least one line before sending." : "Quote #{@quote.number} can't be sent now."
    redirect_to(@quote.editable? ? edit_admin_quote_path(@quote) : preview_admin_quote_path(@quote), alert: message)
  end

  def send_link
    Quote.transaction do
      @quote.mark_sent!(by: current_user, channel: "link")
      @quote.client_link!
    end
    redirect_to new_admin_quote_send_path(@quote), notice: "Quote #{@quote.number} is marked as sent. Copy the link and send it from your phone."
  end

  def send_email
    @form = QuoteSendForm.new(params.expect(quote_send: %i[to cc subject message]))
    return render(:new, status: :unprocessable_content) unless @form.valid?

    quote_send, link = Quote.transaction do
      [ @quote.mark_sent!(by: current_user, channel: "email", recipient: @form.to, cc: @form.cc_header), @quote.client_link! ]
    end
    email = QuoteMailer.send_later(:sent, business: current_business, to: @form.to, kind: "quote_sent", related: @quote,
                                          quote_id: @quote.id, link_id: link.id, subject: @form.subject, message: @form.message, cc: @form.cc_header)
    quote_send.update!(email_message: email)
    redirect_to preview_admin_quote_path(@quote), notice: "Quote #{@quote.number} is on its way to #{@form.to}."
  end

  def default_message
    name = @quote.client.display_name.split.first
    "Hi #{name},\n\nThanks for the chance to quote this work. You can see all the details with the button below. " \
      "The PDF is attached too.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}"
  end
end
