# PAY-04: a client pays an invoice from its link. Pay sends them to a Stripe Checkout page on
# the business's own Stripe account (card, Apple Pay, Google Pay), for the balance or, if the
# business allows it, a part of it they choose. Stripe brings them back to #show; the payment
# itself is recorded only from Stripe's notification (OnlinePayments), so closing the browser
# mid-way loses nothing, and coming back is never taken as proof of payment.
class Client::InvoicePaymentsController < ApplicationController
  # OPS-03: support viewing as a member can look, never pay
  impersonation :read_only
  include ClientLinkAccess

  # Each try starts a Checkout Session at Stripe: a few per link are plenty.
  rate_limit to: 10, within: 10.minutes, by: -> { "#{params[:token]}:#{request.remote_ip}" }, with: -> { too_many_requests }, only: :create, name: "pay-ip"
  rate_limit to: 30, within: 10.minutes, by: -> { params[:token].to_s }, with: -> { too_many_requests }, only: :create, name: "pay-link"

  before_action :require_invoice

  def create
    return back_to_invoice("This invoice can't be paid online right now. Contact #{@business.name} to pay another way.") unless @document.online_payable?

    amount = chosen_amount
    return back_to_invoice(@amount_error) unless amount

    url = OnlinePayments.open_checkout!(@document, amount_cents: amount,
                                        success_url: "#{client_invoice_paid_url(@client_link.token)}?session={CHECKOUT_SESSION_ID}",
                                        cancel_url: client_link_url(@client_link.token, payment: "cancelled"))
    redirect_to "#{CHECKOUT_HOST}#{checkout_path(url)}", allow_other_host: true, status: :see_other
  rescue OnlinePayments::CheckoutInProgress
    back_to_invoice("A payment for this invoice is already going through. It will show here in a moment.")
  rescue PaymentGateway::Error => error
    Rails.error.report(error, handled: true, context: { business_id: @business.id, invoice: @document.uid })
    back_to_invoice("We couldn't start the payment, and nothing was charged. Please try again in a minute.")
  end

  # Back from Checkout. Stripe only sends the client here once the payment went through; the
  # page says whether the invoice shows it yet (the notification may take a moment).
  def show
    @payment = @document.payments.find_by(provider_checkout_id: params[:session].to_s) if params[:session].to_s.start_with?("cs_")
  end

  private

  CHECKOUT_HOST = "https://checkout.stripe.com".freeze

  # Only ever to Stripe's own Checkout page.
  def checkout_path(url)
    uri = URI.parse(url.to_s)
    raise PaymentGateway::Error, "Unexpected Checkout address" unless uri.scheme == "https" && uri.host == "checkout.stripe.com"

    uri.request_uri
  rescue URI::InvalidURIError
    raise PaymentGateway::Error, "Unexpected Checkout address"
  end

  def require_invoice
    render_link_not_found unless @document.is_a?(Invoice) && @document.client_page_visible?
  end

  def back_to_invoice(alert) = redirect_to(client_link_path(@client_link.token), alert:)

  # The balance, or a part of it the client chose (when the business allows part payments): at
  # least OnlinePayments::MINIMUM_PART, leaving nothing or at least that much to pay.
  def chosen_amount
    balance = @document.balance.cents
    return balance unless @business.online_partial_payments? && params[:amount].present?

    cents = Money.parse(params[:amount].to_s.strip, @document.currency).cents
    minimum = OnlinePayments::MINIMUM_PART
    return cents if cents == balance || (cents >= minimum && balance - cents >= minimum)

    @amount_error = "Enter the full #{@document.balance.format}, or #{Money.new(minimum, @document.currency).format} or more " \
                    "that leaves at least #{Money.new(minimum, @document.currency).format} to pay."
    nil
  rescue ArgumentError
    @amount_error = "Enter an amount like 50 or 50.00."
    nil
  end
end
