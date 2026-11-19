# Sending an invoice (PAY-02), as quotes are sent (QTE-04): by email (the branded email with a
# "View invoice" button and the PDF attached), or by getting the link to send from the owner's
# own phone. The first send of a draft or a revision marks the invoice sent; resends of an
# unpaid invoice are recorded the same way.
class Admin::InvoiceSendsController < Admin::BaseController
  include ConfirmedSender

  requires_permission :office
  # Emails per business per hour (shared with quotes' limit), and per invoice per day.
  rate_limit to: EmailMessage::CLIENT_EMAILS_PER_HOUR, within: 1.hour, by: -> { current_business.id }, only: :create, scope: "client-emails",
             with: -> { redirect_to new_admin_invoice_send_path(params[:invoice_id]), alert: "That's a lot of emails in an hour. Try again later." }
  EMAILS_PER_INVOICE_PER_DAY = 5

  before_action :set_invoice
  before_action :require_sendable
  before_action :require_confirmed_sender, only: :create

  def new
    subject, message = usual_wording
    @form = QuoteSendForm.new(to: @invoice.client.primary_email&.value, subject:, message:)
    @template_choices = template_choices
    # The link itself is client-facing: only for accounts that may send (ACC-01), and only once
    # there's something for the client to see.
    @link = ClientLink.active.where(linkable: @invoice).order(created_at: :desc).first if @invoice.client_visible? && current_user.can_send_to_clients?
  end

  def create
    params[:channel] == "link" ? send_link : send_email
  rescue ActiveRecord::RecordInvalid => error
    problems = error.record.errors.full_messages.to_sentence
    redirect_to helpers.staff_invoice_path(@invoice.reload), alert: "Fix the invoice before sending: #{problems}."
  rescue ArgumentError => error # paid or voided since the page loaded
    redirect_to helpers.staff_invoice_path(@invoice.reload), alert: error.message
  end

  private

  def set_invoice = @invoice = Invoice.includes(:client, :line_items).find_by_param!(params[:invoice_id])

  def require_sendable
    return if @invoice.sendable?

    message = if @invoice.line_items.empty? then "Add at least one line before sending."
    else "Invoice #{@invoice.number} is #{@invoice.status_label.downcase}, so it isn't sent again."
    end
    redirect_to(@invoice.editable? ? edit_admin_invoice_path(@invoice) : admin_invoice_path(@invoice), alert: message)
  end

  def send_link
    Invoice.transaction do
      @invoice.mark_sent!(by: current_user, channel: "link")
      @invoice.client_link!
    end
    redirect_to new_admin_invoice_send_path(@invoice), notice: "Invoice #{@invoice.number} is marked as sent. Copy the link and send it from your phone."
  end

  def send_email
    @form = QuoteSendForm.new(params.expect(invoice_send: %i[to cc subject message]))
    valid = @form.valid? # (clears errors, so the daily limit is added after)
    @form.errors.add(:base, "This invoice has been emailed #{EMAILS_PER_INVOICE_PER_DAY} times today. Try again tomorrow.") if too_many_today?
    @template_choices = template_choices unless valid && @form.errors.empty?
    return render(:new, status: :unprocessable_content) unless valid && @form.errors.empty?

    # One transaction: the send and the email record commit together, and the email job is
    # enqueued only after commit, so an invoice is never "sent" without its email.
    Invoice.transaction do
      invoice_send = @invoice.mark_sent!(by: current_user, channel: "email", recipient: @form.to, cc: @form.cc_header)
      link = @invoice.client_link!
      email = InvoiceMailer.send_later(:sent, business: current_business, to: @form.to, kind: "invoice_sent", related: @invoice,
                                              invoice_id: @invoice.id, revision: @invoice.revision, link_id: link.id, subject: @form.subject, message: @form.message, cc: @form.cc_header)
      invoice_send.update!(email_message: email)
    end
    redirect_to admin_invoice_path(@invoice), notice: "Invoice #{@invoice.number} is on its way to #{@form.to}."
  end

  def too_many_today? = @invoice.sends.unscope(:order).where(channel: "email", created_at: 1.day.ago..).count >= EMAILS_PER_INVOICE_PER_DAY

  # NTF-03: the usual wording, then the business's own templates, filled in for this invoice.
  def template_choices
    custom = MessageTemplate.custom.to_a
    return [] if custom.empty?

    values = MessageTemplate::Values.invoice(@invoice).merge(MessageTemplate::Values.sender(current_user, current_business))
    [ [ "Your usual wording", *usual_wording ] ] +
      custom.map { [ _1.name, MessageTemplate.render_subject(_1.subject, values), MessageTemplate.render(_1.body, values) ] }
  end

  # NTF-03: the business's own wording for this email if it has some, else the standard.
  def usual_wording
    subject, message = templated_wording
    [ subject || InvoiceMailer.default_subject(@invoice), message || default_message ]
  end

  def templated_wording
    return if @invoice.revising? # a revised invoice says it's an updated version (the standard note)

    template = MessageTemplate.for_kind("invoice_sent") or return
    values = MessageTemplate::Values.invoice(@invoice).merge(MessageTemplate::Values.sender(current_user, current_business))
    [ MessageTemplate.render_subject(template.subject, values), MessageTemplate.render(template.body, values) ]
  end

  def default_message
    name = @invoice.client.display_name.split.first
    return "Hi #{name},\n\nHere's an updated version of invoice #{@invoice.number}. You can see the details with the button below, " \
           "and the PDF is attached.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}" if @invoice.revising?

    "Hi #{name},\n\nThanks for your business. Your invoice is ready: you can see the details with the button below, " \
      "and the PDF is attached.\n\nAny questions, just reply to this email.\n\n#{current_user.first_name.presence || current_business.name}"
  end
end
