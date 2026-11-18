# Payments staff record against an invoice (PAY-05): cash, checks, bank transfers and the like,
# including part payments; and correcting or deleting one, with a reason the history keeps.
# Online payments (PAY-04) are listed on the invoice but can't be changed here.
class Admin::InvoicePaymentsController < Admin::BaseController
  requires_permission :office

  RECEIPTS_PER_CLIENT_PER_DAY = 5

  before_action :set_invoice
  before_action :set_payment, only: %i[edit update destroy]

  def new
    return redirect_to(helpers.staff_invoice_path(@invoice), alert: cannot_pay_message) unless @invoice.payable?

    @payment = @invoice.payments.new(currency: @invoice.currency, received_on: current_business.today, payment_method: "check")
    @payment.amount = @invoice.balance
  end

  def create
    @payment = @invoice.record_payment!(by: current_user, **payment_params)
    return render(:new, status: :unprocessable_content) if @payment.errors.any?

    redirect_to admin_invoice_path(@invoice), notice: "#{helpers.money(@payment.amount)} recorded. #{balance_notice}#{send_receipt}#{send_nudge}"
  rescue ArgumentError
    redirect_to helpers.staff_invoice_path(@invoice), alert: cannot_pay_message
  end

  def edit; end

  def update
    @invoice.change_payment!(@payment, by: current_user, reason: params[:reason], **payment_params)
    return render(:edit, status: :unprocessable_content) if @payment.errors.any?

    redirect_to admin_invoice_path(@invoice), notice: "Payment changed. #{balance_notice}"
  rescue ActiveRecord::RecordNotFound # deleted by someone else just now
    redirect_to admin_invoice_path(@invoice), alert: "That payment isn't there any more."
  rescue ArgumentError => error
    @payment.assign_attributes(payment_params)
    @reason_error = error.message
    render :edit, status: :unprocessable_content
  end

  def destroy
    @invoice.delete_payment!(@payment, by: current_user, reason: params[:reason])
    redirect_to admin_invoice_path(@invoice), notice: "Payment deleted. #{balance_notice}"
  rescue ActiveRecord::RecordNotFound # deleted by someone else just now
    redirect_to admin_invoice_path(@invoice), alert: "That payment isn't there any more."
  rescue ArgumentError => error
    @delete_reason_error = error.message
    render :edit, status: :unprocessable_content
  end

  private

  def set_invoice = @invoice = Invoice.find_by_param!(params[:invoice_id])

  # Only recorded payments are changed here.
  def set_payment
    @payment = @invoice.payments.find_by_param!(params[:id])
    if @payment.online? then redirect_to admin_invoice_path(@invoice), alert: "Online payments can't be changed here."
    elsif @invoice.void? then redirect_to admin_invoice_path(@invoice), alert: "Invoice #{@invoice.number} is void, so its payments can't change."
    end
  end

  def payment_params = params.expect(payment: %i[amount received_on payment_method reference note]).to_h.symbolize_keys

  # The optional receipt (to the client's email on file), only from accounts that may email
  # clients (ACC-01) and within the hourly cap. Returns the notice's last sentence.
  def send_receipt
    return "" unless params[:send_receipt] == "1"

    to = @invoice.client.primary_email&.value
    if to.nil? then " No receipt sent: #{@invoice.client.display_name} has no email address."
    elsif !current_user.can_send_to_clients? then " No receipt sent: confirm your email address first."
    elsif EmailSuppression.suppressed?(to) then " No receipt sent: the mail server refused #{to} before."
    elsif EmailMessage.hourly_limit_reached? then " No receipt sent: that's a lot of emails in an hour. Try again later."
    elsif EmailMessage.where(kind: "payment_receipt", to:, created_at: 1.day.ago..).count >= RECEIPTS_PER_CLIENT_PER_DAY
      " No receipt sent: #{to} has had #{RECEIPTS_PER_CLIENT_PER_DAY} receipts today."
    else
      PaymentMailer.send_later(:receipt, business: current_business, to:, kind: "payment_receipt", related: @payment, payment_id: @payment.id)
      " Receipt on its way to #{to}."
    end
  end

  # A part payment on an invoice the client hasn't been sent yet (paid on the spot).
  def send_nudge = @invoice.sends.none? && !@invoice.paid? ? " Send the invoice so the client sees what's left." : ""

  def balance_notice
    @invoice.reload
    @invoice.paid? ? "Invoice #{@invoice.number} is paid in full." : "#{helpers.money(@invoice.balance)} left to pay."
  end

  def cannot_pay_message
    if @invoice.revising? then "Send or discard the changes to invoice #{@invoice.number} before recording a payment."
    elsif @invoice.paid? then "Invoice #{@invoice.number} is already paid in full."
    elsif @invoice.void? then "Invoice #{@invoice.number} is void."
    else "Add something to bill before recording a payment."
    end
  end
end
