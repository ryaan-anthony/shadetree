# PAY-08: progress billing, credits and discount shares on an invoice (BillingLedger does the
# arithmetic). Behind split_jobs, with PAY-06.
#
# - kind: "work" bills work (final bills); "progress" bills part of it before it's done, never more
#   than what's left of each line (checked on every save, under PAY-06's lock).
# - A work invoice's shares (its quote's fixed discount, and each quote line's) and its credits
#   (progress billed earlier, then over-billing) are worked out on every save while it's a draft,
#   so they're right when it's sent; once sent they don't change. A void works out the quote's
#   other drafts again.
# - Credits come off before tax as negative lines; the $0 rule looks at the total before them, and
#   a sent invoice with nothing due is Paid at once.
module BillingCredits
  extend ActiveSupport::Concern

  KINDS = %w[work progress].freeze

  included do
    has_many :credits, -> { order(:position, :id) }, class_name: "InvoiceCredit", inverse_of: :invoice, dependent: :delete_all, autosave: true

    validates :kind, inclusion: { in: KINDS }
    validate :progress_within_what_is_left, if: -> { progress? && draft? && association(:line_items).loaded? && billing_credits? }
    validate :keeps_credited_progress, if: -> { sent_at && association(:line_items).loaded? }
    before_save :work_out_credits, prepend: true, if: -> { kind == "work" && status_in_database.in?([ nil, "draft" ]) && billing_credits? && !@restoring }
  end

  def progress? = kind == "progress"

  # Prices the lines with the shares, and the pre-tax credits as negative lines (credits: false is
  # the total before credits, which the $0 rule looks at).
  def totals(credits: true)
    Pricing::DocumentTotals.new(currency:, discount: pricing_discount, prices_include_tax:, share: Money.new(quote_discount_share_cents.to_i, currency),
                                lines: current_line_items.map { _1.to_pricing(tax_rate_list) } + (credits ? pre_tax_credits.map(&:to_pricing) : []))
  end

  def pre_tax_credits = credits.reject(&:marked_for_destruction?).select(&:pre_tax?)

  def quote_discount_share = Money.new(quote_discount_share_cents.to_i, currency)

  # #289: the $0 rule looks at the total before credits (PAY-08).
  def sendable_total? = totals(credits: false).total.positive?

  # Nothing to pay once sent: Paid at once (a credit can bring a total to zero).
  def nothing_due? = billing_credits? && (total_cents.zero? || (total_cents.negative? && credits.any?))

  def billing_credits? = (quote_id || job_id).present? && QuoteWork.split?(business)

  # The invoices whose progress this one's credits use, still counted, that a void would undo.
  def crediting_invoices = Invoice.where(id: InvoiceCredit.counted.where(source_invoice_id: id).where.not(invoice_id: id).select(:invoice_id)).order(:id)

  # Drafts of the same quote (or job) work out their shares and credits again, after a void.
  def rework_drafts!
    return unless billing_credits?

    drafts = Invoice.where(status: "draft", kind: "work").where.not(id:)
    drafts = quote_id ? drafts.where(quote_id:) : drafts.where(id: InvoiceJob.where(job_id:).select(:invoice_id))
    drafts.order(:id).each { _1.save!(validate: false) }
  end

  private

  def lock_billing!
    quote_id ? QuoteWork.lock!(quote_id) : WorkBilling.lock!(jobs: [ job_id ])
  end

  def work_out_credits
    lock_billing!
    ledger = BillingLedger.for(self)
    lines = current_line_items
    finals = lines.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }
    share_lines(ledger, lines, finals)
    self.quote_discount_share_cents = ledger.quote_share_cents(finals)

    work = finals.select(&:quote_line_item_id)
    parts = quote_discount_share.allocate(work.map { BillingLedger.subtotal_cents(_1) })
    caps = finals.map { |line| [ line, BillingLedger.subtotal_cents(line) - (work.index(line) ? parts[work.index(line)].cents : 0) ] }
    others = lines.reject { _1.job_line_item_id || _1.quote_line_item_id }.sum { BillingLedger.subtotal_cents(_1) }.clamp(0..)
    wanted = ledger.credits_for(caps, others_cap: others)
    return if wanted == pre_tax_credits.map { _1.snapshot.symbolize_keys }

    credits.each(&:mark_for_destruction)
    wanted.each { credits.build(**_1, business:) }
  end

  # Each quote line's fixed discount, shared over this invoice's bills of it in order.
  def share_lines(ledger, lines, finals)
    lines.each { _1.discount_share_cents = 0 unless finals.include?(_1) }
    finals.select(&:quote_line_item_id).group_by(&:quote_line_item_id).each do |id, group|
      group.each { _1.discount_share_cents = 0 }
      line = ledger.quote_line(id) or next
      left = ledger.line_share_cents(line, group)
      group.each do |item|
        item.discount_share_cents = [ left, BillingLedger.subtotal_cents(item).clamp(0..) ].min
        left -= item.discount_share_cents
      end
    end
  end

  # "Roof: only $500.00 is left to bill."
  def progress_within_what_is_left
    lock_billing!
    ledger = BillingLedger.for(self)
    current_line_items.reject(&:final).select { _1.job_line_item_id || _1.quote_line_item_id }
                      .group_by { _1.job_line_item_id ? [ :job, _1.job_line_item_id ] : [ :quote, _1.quote_line_item_id ] }.each do |(kind, id), group|
      work = kind == :job ? ledger.job_line(id) : ledger.quote_line(id)
      left = work ? ledger.left_cents(work) : 0
      next if group.sum { BillingLedger.subtotal_cents(_1) } <= left

      errors.add(:base, "#{group.first.name.presence || "Item"}: only #{Money.new(left, currency).format} is left to bill.")
    end
  end

  # Progress credited on a later invoice stays as it was billed: void that invoice first.
  def keeps_credited_progress
    used = InvoiceCredit.counted.where(source_line_item_id: line_items.filter_map(&:id)).where.not(invoice_id: id).group(:source_line_item_id).sum(:amount_cents)
    short = line_items.select { (taken = used[_1.id]) && (_1.marked_for_destruction? || BillingLedger.subtotal_cents(_1) < taken) }
    errors.add(:base, "#{short.map(&:name).to_sentence} #{short.one? ? "is" : "are"} credited on #{crediting_invoices.pluck(:number).to_sentence}. Void that first.") if short.any?
  end
end
