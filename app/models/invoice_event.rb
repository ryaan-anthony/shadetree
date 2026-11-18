# What happened to an invoice, for its history (PAY-01): created ({ "from" => "job"|"quote",
# "number" }), and each change of status: sent, partially_paid, paid, voided ({ "reason" }),
# revised ({ "revision" }), revision_discarded ({ "revision" }, back to what was sent) and reopened
# (no longer paid); PAY-05's payment_recorded, payment_changed ({ "before", "after", "reason" })
# and payment_deleted ({ "reason" }), each with the payment's summary.
class InvoiceEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[created sent revised revision_discarded partially_paid paid voided reopened
             payment_recorded payment_changed payment_deleted].freeze

  belongs_to_business_record :invoice
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(invoice, kind, by:, **data)
    create!(business: invoice.business, invoice:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
