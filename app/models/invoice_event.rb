# What happened to an invoice, for its history (PAY-01): created ({ "from" => "job"|"quote",
# "number" }), and each change of status: sent, partially_paid, paid, voided ({ "reason" }),
# revised ({ "revision" }) and reopened.
class InvoiceEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[created sent revised partially_paid paid voided reopened].freeze

  belongs_to_business_record :invoice
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  def self.record!(invoice, kind, by:, **data)
    create!(business: invoice.business, invoice:, kind: kind.to_s, user: by, data:, occurred_at: Time.current)
  end
end
