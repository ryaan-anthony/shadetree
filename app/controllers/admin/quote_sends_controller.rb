# Sending a quote (QTE-04): by email (the branded email with a "View quote" button and the PDF
# attached), or by getting the link to send from the owner's own phone. The first send of
# either kind marks the quote sent and counts toward plan usage (BIL-02); resends don't.
class Admin::QuoteSendsController < Admin::BaseController
  include ConfirmedSender

  requires_permission :office
  # Emails per business per hour (one count with invoices' sends), and per quote per day (below): the platform's sending domain
  # isn't a relay. Only a quote's first send counts toward plan usage, so usage can't be the cap.
  rate_limit to: EmailMessage::CLIENT_EMAILS_PER_HOUR, within: 1.hour, by: -> { current_business.id }, only: :create, scope: "client-emails",
             with: -> { redirect_to new_admin_quote_send_path(@quote || params[:quote_id]), alert: "That's a lot of emails in an hour. Try again later." }
  EMAILS_PER_QUOTE_PER_DAY = 5

  before_action :set_quote
  before_action :require_sendable
  before_action :require_confirmed_sender, only: :create
  before_action :require_quote_allowance, only: :create

  def new
    @form = QuoteSendForm.new(to: @quote.client.primary_email&.value, subject: QuoteMailer.default_subject(@quote),
                              message: default_message)
    # The link itself is client-facing: only for accounts that may send (ACC-01).
    @link = ClientLink.active.where(linkable: @quote).order(created_at: :desc).first unless @quote.draft? || !current_user.can_send_to_clients?
  end

  def create
    params[:channel] == "link" ? send_link : send_email
  rescue QuoteLimitReached
    redirect_to new_admin_quote_send_path(@quote, from: ("setup" if from_setup?)), alert: quote_limit_message
  end

  private

  # BIL-03: a quote's first send counts toward the plan's quotes; over the limit (and its one
  # extra), new quotes wait. Resends of quotes already sent never count.
  def require_quote_allowance
    return if !@quote.counts_toward_usage? || current_business.entitlements.can_send_new_quote?

    redirect_to new_admin_quote_send_path(@quote, from: ("setup" if from_setup?)), alert: quote_limit_message
  end

  class QuoteLimitReached < StandardError; end

  # Re-checked inside the send's transaction with the business row locked, so two first sends
  # at the boundary can't both take the last allowance.
  def claim_quote_allowance!
    return unless @quote.counts_toward_usage?

    current_business.lock!
    raise QuoteLimitReached unless Entitlements.for(current_business).can_send_new_quote?
  end

  def quote_limit_message = "You've used this period's quotes. New quotes can be sent again on #{l(current_business.entitlements.period.resets_on)}."

  def set_quote = @quote = Quote.includes(:client, :line_items).find_by_param!(params[:quote_id])

  def require_sendable
    return if @quote.sendable?

    message = if @quote.line_items.empty? then "Add at least one line before sending."
    elsif @quote.past_expiry? then "Quote #{@quote.number} expired on #{l(@quote.expires_on)}. Change its valid-until date before sending."
    else "Quote #{@quote.number} can't be sent now."
    end
    redirect_to(@quote.editable? ? edit_admin_quote_path(@quote, from: ("setup" if from_setup?)) : admin_quote_path(@quote), alert: message)
  end

  def send_link
    Quote.transaction do
      claim_quote_allowance!
      @quote.mark_sent!(by: current_user, channel: "link")
      @quote.client_link!
    end
    redirect_to new_admin_quote_send_path(@quote), notice: "Quote #{@quote.number} is marked as sent. Copy the link and send it from your phone."
  end

  def send_email
    @form = QuoteSendForm.new(params.expect(quote_send: %i[to cc subject message]))
    valid = @form.valid? # (clears errors, so the daily limit is added after)
    @form.errors.add(:base, "This quote has been emailed #{EMAILS_PER_QUOTE_PER_DAY} times today. Try again tomorrow.") if too_many_today?
    return render(:new, status: :unprocessable_content) unless valid && @form.errors.empty?

    # One transaction: the send, the usage event and the email record commit together, and the
    # email job is enqueued only after commit, so a quote is never "sent" without its email.
    Quote.transaction do
      claim_quote_allowance!
      quote_send = @quote.mark_sent!(by: current_user, channel: "email", recipient: @form.to, cc: @form.cc_header)
      link = @quote.client_link!
      email = QuoteMailer.send_later(:sent, business: current_business, to: @form.to, kind: "quote_sent", related: @quote,
                                            quote_id: @quote.id, revision: @quote.revision, link_id: link.id, subject: @form.subject, message: @form.message, cc: @form.cc_header)
      quote_send.update!(email_message: email)
    end
    redirect_after_setup_step admin_quote_path(@quote), notice: "Quote #{@quote.number} is on its way to #{@form.to}."
  end

  def too_many_today? = @quote.sends.unscope(:order).where(channel: "email", created_at: 1.day.ago..).count >= EMAILS_PER_QUOTE_PER_DAY

  def default_message
    name = @quote.client.display_name.split.first
    "Hi #{name},\n\nThanks for the chance to quote this work. You can see all the details with the button below. " \
      "The PDF is attached too.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}"
  end
end
