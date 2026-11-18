# What a client was sent before an invoice was revised (PAY-01): the snapshot from
# Invoice#snapshot, as revision `number`.
class InvoiceRevision < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :invoice
  belongs_to :revised_by, class_name: "User", optional: true

  def total = Money.new(snapshot["total_cents"].to_i, snapshot["currency"])
end
