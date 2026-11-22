# #289: a quote or invoice whose total is $0.00 (a "price on quote" service left at zero, say)
# doesn't go out by accident. Its first send asks first: the send page explains, and only
# "Send it at $0.00" (zero_total=confirmed) shows the ways to send. Resends of something
# already out aren't asked again.
#
#   include ZeroTotalGuard
#   zero_total_guard :@quote, path: :new_admin_quote_send_path
module ZeroTotalGuard
  extend ActiveSupport::Concern

  CONFIRMED = "confirmed".freeze

  class_methods do
    def zero_total_guard(ivar, path:)
      define_method(:zero_total_document) { instance_variable_get(ivar) }
      define_method(:zero_total_path) { public_send(path, zero_total_document) }
      before_action :require_zero_total_confirmed, only: :create
    end
  end

  included do
    helper_method :zero_total?, :zero_total_confirmed?, :unpriced_lines
  end

  private

  # A first send (draft or revision) of a document that totals nothing.
  def zero_total? = zero_total_document.draft? && !zero_total_document.sendable_total?
  def zero_total_confirmed? = params[:zero_total] == CONFIRMED

  # Lines with no price, named on the send page even when the total isn't zero.
  def unpriced_lines = zero_total_document.line_items.select { _1.unit_price_cents.to_i.zero? }

  def require_zero_total_confirmed
    return if !zero_total? || zero_total_confirmed?

    redirect_to zero_total_path, alert: "The total is #{helpers.money(zero_total_document.totals.total)}. Add prices, or confirm you mean to send it at that."
  end
end
