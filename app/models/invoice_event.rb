# What happened to an invoice, for its history (PAY-01): created ({ "from" => "job"|"quote",
# "number" }), and each change of status: sent, partially_paid, paid, voided ({ "reason" }),
# revised ({ "revision" }), revision_discarded ({ "revision" }, back to what was sent) and reopened
# (no longer paid); PAY-05's payment_recorded, payment_changed ({ "before", "after", "reason" })
# and payment_deleted ({ "reason" }), each with the payment's summary; CAT-08's repriced
# ({ "location", "changed" }); PAY-04's payment_received (paid online), payment_refunded and
# payment_disputed ({ "refunded_cents", "dispute" }), from Stripe's notifications; PAY-08's
# progress_refitted ({ "lowered", "removed" }: a progress draft fitted to what's left).
class InvoiceEvent < ApplicationRecord
  include BusinessOwned
  include SupportAttribution # OPS-03

  KINDS = %w[created sent revised revision_discarded partially_paid paid voided reopened
             payment_recorded payment_changed payment_deleted repriced payment_received payment_refunded payment_disputed progress_refitted].freeze

  belongs_to_business_record :invoice
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(invoice, kind, by:, **data)
    create!(business: invoice.business, invoice:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
