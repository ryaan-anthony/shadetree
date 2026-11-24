# JOB-09: a job's share of a quote line: "6 of the 10 trees". Claims are the one source of which
# job holds what; a job line's quote line is read through its claim, and the quote line's
# claimed_quantity is the sum of its live claims, kept by QuoteWork under its lock order.
#
# Live: its job isn't cancelled, or, with no job (PAY-06's direct billing), its invoice line's
# invoice isn't void. A cancelled job keeps its claims (not live), so a reopen can take them back.
# A completed job's claim keeps what it booked: a shortfall isn't freed, and a reopen returns the
# job's lines to it.
class JobClaim < ApplicationRecord
  include BusinessOwned

  belongs_to :job, optional: true
  belongs_to :quote_line_item
  belongs_to :job_line_item, optional: true
  belongs_to :invoice_line_item, optional: true

  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  LIVE = <<~SQL.squish.freeze
    ((job_claims.job_id IS NOT NULL AND EXISTS (SELECT 1 FROM jobs WHERE jobs.id = job_claims.job_id AND jobs.status <> 'cancelled'))
      OR (job_claims.job_id IS NULL AND EXISTS (SELECT 1 FROM invoice_line_items JOIN invoices ON invoices.id = invoice_line_items.invoice_id
                                                WHERE invoice_line_items.id = job_claims.invoice_line_item_id AND invoices.status <> 'void')))
  SQL
  scope :live, -> { where(Arel.sql(LIVE)) }

  # Quote lines whose claimed_quantity isn't the sum of their live claims: always none (the
  # reconcile test), a list to look into otherwise.
  def self.unreconciled_lines
    sums = unscoped.live.where("job_claims.quote_line_item_id = quote_line_items.id").select("COALESCE(SUM(job_claims.quantity), 0)")
    QuoteLineItem.where("quote_line_items.claimed_quantity <> (#{sums.to_sql})")
  end
end
