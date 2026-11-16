# A version of a quote the client was sent and that has since been revised (QTE-06): what it
# said (the snapshot QuoteResponse.snapshot_of makes), its PDF, and where it stood when it was
# superseded. The quote itself is always the latest revision.
class QuoteRevision < ApplicationRecord
  include BusinessOwned

  belongs_to_business_record :quote
  belongs_to :pdf_blob, class_name: "ActiveStorage::Blob", optional: true
  belongs_to :revised_by, class_name: "User", optional: true

  def readonly? = persisted?
  def total = Money.new(snapshot.dig("totals", "total_cents").to_i, snapshot["currency"])

  # What changed from this revision to the next one (or to the quote as it is now).
  def changes_to(next_snapshot) = QuoteRevisionDiff.new(snapshot, next_snapshot).changes
end
