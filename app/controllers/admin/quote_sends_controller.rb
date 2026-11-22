# Sending a quote (QTE-04): by email (the branded email with a "View quote" button and the PDF
# attached), or by getting the link to send from the owner's own phone. The first send of
# either kind marks the quote sent and counts toward plan usage (BIL-02); resends don't.
class Admin::QuoteSendsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  include ConfirmedSender
  include ZeroTotalGuard

  requires_permission :office
  include OwnQuoteAccess
  allow_any_member # QTE-07: also members who send the quotes they drafted (set_quote decides)
  # Emails per business per hour (one count with invoices' sends), and per quote per day (below): the platform's sending domain
  # isn't a relay. Only a quote's first send counts toward plan usage, so usage can't be the cap.
  rate_limit to: EmailMessage::CLIENT_EMAILS_PER_HOUR, within: 1.hour, by: -> { current_business.id }, only: :create, scope: "client-emails",
             with: -> { redirect_to new_admin_quote_send_path(@quote || params[:quote_id]), alert: "That's a lot of emails in an hour. Try again later." }
  EMAILS_PER_QUOTE_PER_DAY = 5

  before_action :set_quote
  before_action :require_sendable
  before_action :require_confirmed_sender, only: :create
  before_action :require_quote_allowance, only: :create
  zero_total_guard :@quote, path: :new_admin_quote_send_path

  def new
    subject, message = usual_wording
    @form = QuoteSendForm.new(to: @quote.client.primary_email&.value, subject:, message:)
    @template_choices = template_choices
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

  # QTE-07: office staff send any quote; members with "Send their own quotes" only the ones they
  # drafted from requests (resends of them too); anyone else is refused.
  def set_quote
    scope = if !own_quotes_only? then Quote.all
    elsif can?(:send_own_quotes) && can?(:quote_requests) # never a revision the office started, nor a copy of an approved one
      Quote.where(created_by_id: current_user.id, revision: 1, status: %w[draft sent]).where.not(service_request_id: nil)
    else return deny!(:office, "can't send quotes")
    end
    @quote = scope.includes(:client, :line_items).find_by_param!(params[:quote_id])
  end

  # Where to go after (or instead of) sending: the quote's page for office staff; for members
  # sending their own, the draft while it's one, else their start page.
  helper_method def after_send_path(quote) = own_quotes_only? ? (quote.editable? ? edit_admin_quote_path(quote) : admin_root_path) : admin_quote_path(quote)

  def require_sendable
    return if @quote.sendable? || @quote.copy_sendable? # #289: a copy of an approved quote

    message = if @quote.client.erased? then "This client's details were erased, so nothing more can be sent to them."
    elsif @quote.line_items.empty? then "Add at least one line before sending."
    elsif @quote.past_expiry? then "Quote #{@quote.number} expired on #{l(@quote.expires_on)}. Change its valid-until date before sending."
    else "Quote #{@quote.number} can't be sent now."
    end
    redirect_to(@quote.editable? ? edit_admin_quote_path(@quote, from: ("setup" if from_setup?)) : after_send_path(@quote), alert: message)
  end

  def send_link
    Quote.transaction do
      claim_quote_allowance!
      @quote.mark_sent!(by: current_user, channel: "link")
      @quote.client_link!
    end
    track_first_quote
    redirect_to new_admin_quote_send_path(@quote), notice: "Quote #{@quote.number} is marked as sent. Copy the link and send it from your phone."
  end

  def send_email
    @form = QuoteSendForm.new(params.expect(quote_send: %i[to cc subject message]))
    valid = @form.valid? # (clears errors, so the daily limit is added after)
    only_on_file if valid && own_quotes_only?
    @form.errors.add(:base, "This quote has been emailed #{EMAILS_PER_QUOTE_PER_DAY} times today. Try again tomorrow.") if too_many_today?
    @template_choices = template_choices unless valid && @form.errors.empty?
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
    track_first_quote
    redirect_after_setup_step after_send_path(@quote), notice: "Quote #{@quote.number} is on its way to #{@form.to}."
  end

  # QTE-07: someone sending their own quote sends to the client's addresses on file only.
  def only_on_file
    on_file = @quote.client.contact_methods.select(&:email?).map { _1.value.downcase }
    outside = [ @form.to, *@form.cc_list ].compact.reject { on_file.include?(_1.downcase) }
    @form.errors.add(:base, "Send it to the client's email on file. Ask the office to send it anywhere else.") if outside.any?
  end

  # MKT-04: the funnel's last step, when this send was the business's first.
  def track_first_quote
    Analytics.track("First Quote Sent", request:) if @quote.first_quote_sent?
  end

  def too_many_today? = @quote.sends.unscope(:order).where(channel: "email", created_at: 1.day.ago..).count >= EMAILS_PER_QUOTE_PER_DAY

  # NTF-03: the usual wording, then the business's own templates, filled in for this quote.
  def template_choices
    custom = MessageTemplate.custom.to_a
    return [] if custom.empty?

    values = MessageTemplate::Values.quote(@quote).merge(MessageTemplate::Values.sender(current_user, current_business))
    [ [ "Your usual wording", *usual_wording ] ] +
      custom.map { [ _1.name, MessageTemplate.render_subject(_1.subject, values), MessageTemplate.render(_1.body, values) ] }
  end

  # NTF-03: the business's own wording for this email if it has some, else the standard.
  def usual_wording
    subject, message = templated_wording unless @quote.approved? # a copy isn't asking for an answer (#289)
    [ subject || QuoteMailer.default_subject(@quote), message || default_message ]
  end

  def templated_wording
    template = MessageTemplate.for_kind("quote_sent") or return
    values = MessageTemplate::Values.quote(@quote).merge(MessageTemplate::Values.sender(current_user, current_business))
    [ MessageTemplate.render_subject(template.subject, values), MessageTemplate.render(template.body, values) ]
  end

  def default_message
    name = @quote.client.display_name.split.first
    if @quote.approved? # #289: a copy of what they approved
      return "Hi #{name},\n\nHere's a copy of the quote you approved, for your records. You can see it any time with the button below, " \
             "and the PDF is attached.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}"
    end
    "Hi #{name},\n\nThanks for the chance to quote this work. You can see all the details with the button below. " \
      "The PDF is attached too.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}"
  end
end
