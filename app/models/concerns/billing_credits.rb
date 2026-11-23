# PAY-08: progress billing, credits and discount shares on an invoice (BillingLedger does the
# arithmetic). Behind split_jobs, with PAY-06.
#
# - kind: "work" bills work (final bills); "progress" bills part of it before it's done, never more
#   than what's left of each line: every line when it's made and when it's first sent, and a line
#   raised on a revision (under PAY-06's lock).
# - A work invoice's shares (its quote's fixed discount, and each quote line's) and its credits
#   (progress billed earlier, then over-billing) are worked out on every save until it's first
#   sent, so they're right when it goes out. Once sent they don't change: a revision is checked
#   against them instead. A void, or a change to progress a draft credits, works the quote's
#   other drafts out again.
# - Credits come off before tax as negative lines; the $0 rule looks at the total before them, and
#   a sent invoice with nothing due is Paid at once.
# - Progress credited on a later invoice that went out stays as it was billed (amount, tax and
#   whether prices include tax) until that invoice is voided (owner, 2026-11-23).
module BillingCredits
  extend ActiveSupport::Concern

  KINDS = %w[work progress].freeze

  included do
    has_many :credits, -> { order(:position, :id).includes(:source_invoice) }, class_name: "InvoiceCredit", inverse_of: :invoice,
                                                                                dependent: :delete_all, autosave: true

    validates :kind, inclusion: { in: KINDS }
    validate :progress_within_what_is_left, if: -> { progress? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    validate :keeps_credited_progress, if: -> { progress? && sent_at_in_database && association(:line_items).loaded? }
    validate :keeps_its_credits, if: -> { kind == "work" && sent_at_in_database && draft? && association(:line_items).loaded? && credits.any? }
    validate :progress_matches_on_tax_inclusion, if: -> { draft? && billing_credits? && (new_record? || prices_include_tax_changed? || sent_at_in_database.nil?) }
    before_save :work_out_credits, prepend: true, if: -> { kind == "work" && sent_at_in_database.nil? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    before_save { @progress_changed = progress? && sent_at_in_database && line_items.any?(&:changed_for_autosave?) }
    after_save(if: -> { @progress_changed }) { rework_drafts! }
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
  def nothing_due? = billing_credits? && total_cents.zero?

  def billing_credits? = (quote_id || job_id).present? && QuoteWork.split?(business)

  # The invoices that went out whose credits use this one's progress, which a void would undo.
  def crediting_invoices = Invoice.where(id: InvoiceCredit.counted.where(source_invoice_id: id).where.not(invoice_id: id).select(:invoice_id)).order(:id)

  def credited_later? = progress? && sent_at.present? && billing_credits? && crediting_invoices.exists?

  # Drafts of the same quote (or job) never sent work out their shares and credits again.
  def rework_drafts!
    return unless billing_credits?

    drafts = Invoice.where(status: "draft", kind: "work", sent_at: nil).where.not(id:)
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
    parts = quote_discount_share.allocate(work.map { BillingLedger.subtotal_cents(_1, currency) })
    caps = finals.map { |line| [ line, BillingLedger.subtotal_cents(line, currency) - (work.index(line) ? parts[work.index(line)].cents : 0) ] }
    others = lines.reject { _1.job_line_item_id || _1.quote_line_item_id }.sum { BillingLedger.subtotal_cents(_1, currency) }.clamp(0..)
    wanted = ledger.credits_for(caps, others_cap: others, bases: tax_bases)
    return if wanted == pre_tax_credits.map { _1.snapshot.symbolize_keys }

    credits.each(&:mark_for_destruction)
    wanted.each { credits.build(**_1, business:) }
  end

  # What each tax rate is charged on before credits.
  def tax_bases
    totals(credits: false).lines.each_with_object(Hash.new(0)) { |line, bases| line.line.tax_rates.each { bases[_1] += line.taxable.cents } }
  end

  # Each quote line's fixed discount, shared over this invoice's bills of it in order.
  def share_lines(ledger, lines, finals)
    lines.each { _1.discount_share_cents = 0 unless finals.include?(_1) }
    finals.select(&:quote_line_item_id).group_by(&:quote_line_item_id).each do |id, group|
      group.each { _1.discount_share_cents = 0 }
      line = ledger.quote_line(id) or next
      left = ledger.line_share_cents(line, group)
      group.each do |item|
        item.discount_share_cents = [ left, BillingLedger.subtotal_cents(item, currency).clamp(0..) ].min
        left -= item.discount_share_cents
      end
    end
  end

  # "Roof: only $500.00 is left to bill." Until it's first sent, every line (so a draft sent after
  # the final bill is refused); on a revision, only what's raised or added.
  def progress_within_what_is_left
    lock_billing!
    ledger = BillingLedger.for(self)
    revising = sent_at_in_database.present?
    current_line_items.reject(&:final).select { _1.job_line_item_id || _1.quote_line_item_id }
                      .group_by { _1.job_line_item_id ? [ :job, _1.job_line_item_id ] : [ :quote, _1.quote_line_item_id ] }.each do |(kind, id), group|
      asked = group.sum { BillingLedger.subtotal_cents(_1, currency) }
      next if revising && asked <= group.sum { held_before(_1) }

      work = kind == :job ? ledger.job_line(id) : ledger.quote_line(id)
      left = work ? ledger.left_cents(work) : 0
      next if asked <= left

      errors.add(:base, "#{group.first.name.presence || "Item"}: only #{Money.new(left, currency).format} is left to bill.")
    end
  end

  # A line's subtotal as saved (zero for a new one).
  def held_before(line)
    return 0 if line.new_record?

    BillingLedger.subtotal_cents(InvoiceLineItem.new(line.attributes.merge(line.changed_attributes).except("id")), currency)
  end

  # Progress credited on a later invoice stays as it was billed: void that invoice first.
  def keeps_credited_progress
    used = InvoiceCredit.counted.where(source_line_item_id: line_items.filter_map(&:id)).where.not(invoice_id: id).group(:source_line_item_id).sum(:amount_cents)
    return if used.empty?

    short = line_items.select do |line|
      (taken = used[line.id]) && (line.marked_for_destruction? || BillingLedger.subtotal_cents(line, currency) < taken || line.taxable_changed? || line.tax_rates_changed?)
    end
    short = line_items.select { used[_1.id] } if short.empty? && (tax_rates_changed? || prices_include_tax_changed?)
    return if short.empty?

    errors.add(:base, "#{short.map { _1.name.presence || "Item" }.to_sentence} #{short.one? ? "is" : "are"} credited on " \
                      "#{crediting_invoices.pluck(:number).to_sentence}, so its amount and tax stay as billed. Void that invoice first.")
  end

  # A sent work invoice's revision keeps its shares and credits: it can't go below them.
  def keeps_its_credits
    before = totals(credits: false)
    after = totals
    return unless after.subtotal.negative? || after.discount < before.discount || after.taxes.any? { _1.amount.negative? }

    errors.add(:base, "That takes #{number} below what it credits for #{pre_tax_credits.map { _1.source_invoice.number }.uniq.to_sentence}. Void it and bill again instead.")
  end

  # Progress and the bills that credit it agree on whether prices include tax (else tax would be
  # credited at a different base): a progress invoice matches its work, a work invoice its progress.
  def progress_matches_on_tax_inclusion
    source = progress? ? (quote || job) : nil
    mismatched = if source then source.prices_include_tax != prices_include_tax
    else
      BillingLedger.for(self).progress.select { _1.invoice.sent_at && _1.invoice.prices_include_tax != prices_include_tax }.map { _1.invoice.number }.uniq.presence
    end
    return unless mismatched

    errors.add(:prices_include_tax, source ? "must match #{source.number} (#{source.prices_include_tax ? "prices include tax" : "tax is added"})" \
                                           : "must match #{mismatched.to_sentence}, whose progress it credits")
  end
end
