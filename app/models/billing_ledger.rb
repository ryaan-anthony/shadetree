# PAY-08: what's been billed of a quote's work (or of a job without a quote), read once under
# PAY-06's lock: final bills, progress billed before the work was done, and what's been credited.
# Amounts are line subtotals in cents (after the line's own discount and share, before the
# invoice's discount and tax); a credit is a negative line, so the invoice's discount and tax
# apply to what's left as they did to the progress.
#
# - Progress on a job line is credited on that line's final bill; progress on a quote line, or on
#   the line of a job later cancelled, on its quote line's final bills (its "home").
# - Over-billed: progress not yet credited on a home with nothing left to bill (no to-do quantity
#   and every claim billed or cancelled; QTE-09's Not going ahead counts once it exists).
# - Only what's on invoices that went out is credited, and only credits on invoices that went out
#   count as used; a draft's are worked out again when it's sent.
# - Discount base S: the quote's value after line discounts, billed quantity at the price it was
#   billed at, completed quantity at the job's, the rest at the quote's current price (QTE-10).
#   W: quote work on final bills that went out, and this invoice's.
#
#   ledger = BillingLedger.new(quote:, except: invoice)
#   ledger.over_billed_cents, ledger.left_cents(job_line), ledger.quote_share_cents(lines)
class BillingLedger
  attr_reader :quote, :jobs, :progress

  def initialize(quote: nil, job: nil, except: nil)
    @quote = quote
    @jobs = quote ? quote.jobs.to_a : [ job ]
    @except_id = except&.id
    @quote_lines = (quote ? quote.line_items.to_a : []).index_by(&:id)
    @jobs_by_id = @jobs.index_by(&:id)
    @job_lines = JobLineItem.where(job_id: @jobs_by_id.keys).includes(:claim).to_a.index_by(&:id)
    bills = InvoiceLineItem.where.not(invoice_status: "void").includes(:invoice)
                           .where("invoice_line_items.job_line_item_id IN (:jobs) OR invoice_line_items.quote_line_item_id IN (:quotes)",
                                  jobs: @job_lines.keys.presence || [ 0 ], quotes: @quote_lines.keys.presence || [ 0 ])
    bills = bills.where.not(invoice_id: @except_id) if @except_id
    @finals, @progress = bills.to_a.partition(&:final)
    @progress.sort_by! { [ _1.invoice.sent_at || Time.current, _1.invoice_id, _1.position, _1.id ] }
    @used = InvoiceCredit.counted.where(source_line_item_id: @progress.map(&:id)).where.not(invoice_id: @except_id)
                         .group(:source_line_item_id).sum(:amount_cents)
  end

  def quote_line(id) = @quote_lines[id]
  def job_line(id) = @job_lines[id]

  # Done: nothing to do and every live job on it completed (progress billing is for work not done).
  def done?(line) = line.to_do_quantity <= 0 && live_job_lines(line).all? { @jobs_by_id[_1.job_id].status == "completed" }

  def self.for(invoice) = new(quote: invoice.quote, job: (invoice.job unless invoice.quote), except: invoice)

  # A line's subtotal in cents: quantity × price, less its own discount and share.
  def self.subtotal_cents(line) = Pricing::DocumentTotals.new(currency: line.document_currency, lines: [ line.to_pricing([]) ]).lines.first.subtotal.cents

  # --- Progress and credits ---------------------------------------------------------------

  def amount_cents(progress_line) = (@amounts ||= {})[progress_line.id] ||= self.class.subtotal_cents(progress_line)

  # Progress that went out, less what's been credited of it.
  def remaining_cents(progress_line)
    return 0 unless progress_line.invoice.sent_at

    [ amount_cents(progress_line) - @used.fetch(progress_line.id, 0), 0 ].max
  end

  # Where a line's progress is credited: [:job, job line id] or [:quote, quote line id].
  def home(line)
    job_line = @job_lines[line.job_line_item_id]
    if job_line && @jobs_by_id[job_line.job_id].status != "cancelled" then [ :job, job_line.id ]
    elsif line.quote_line_item_id then [ :quote, line.quote_line_item_id ]
    elsif line.job_line_item_id then [ :job, line.job_line_item_id ]
    end
  end

  def pool(home) = (@pools ||= @progress.group_by { home(_1) })[home].to_a

  # Nothing left to bill: a job line with a final bill (or on a cancelled job); a quote line with
  # nothing to do whose live claims are all billed. `billed` adds this invoice's final bills.
  def nothing_left?(home, billed: [])
    kind, id = home
    billed_ids = billed_job_line_ids + billed.filter_map(&:job_line_item_id)
    if kind == :job
      job_line = @job_lines[id]
      return job_line.nil? || billed_ids.include?(id) || @jobs_by_id[job_line.job_id].status == "cancelled"
    end
    line = @quote_lines[id] or return true
    line.to_do_quantity <= 0 && live_job_lines(line).all? { billed_ids.include?(_1.id) }
  end

  def over_billed_cents(billed: []) = over_billed(billed:).sum { remaining_cents(_1) }

  # Progress lines whose home has nothing left to bill, with something not yet credited.
  def over_billed(billed: [])
    @progress.select { remaining_cents(_1).positive? && (home = home(_1)) && nothing_left?(home, billed:) }
  end

  # Credits for an invoice's final bills: [[line, cap_cents]] in order, each cap what this bill
  # takes for the line after its discount share. Each line takes min(progress not yet credited,
  # what's left of its cap): its job line's own first, then its quote line's. Then over-billing,
  # up to what's left of the invoice. Returns attributes for InvoiceCredit.
  def credits_for(lines_with_caps, others_cap: 0)
    left = Hash.new { |hash, line| hash[line] = remaining_cents(line) }
    credits = []
    lines_with_caps.each do |line, cap|
      [ home(line), ([ :quote, line.quote_line_item_id ] if line.quote_line_item_id) ].compact.uniq.each do |from|
        pool(from).each do |progress|
          take = [ left[progress], cap ].min
          next unless take.positive?

          credits << credit(:progress, progress, take)
          left[progress] -= take
          cap -= take
        end
      end
      others_cap += cap
    end
    over_billed(billed: lines_with_caps.map(&:first)).each do |progress|
      take = [ left[progress], others_cap ].min
      next unless take.positive?

      credits << credit(:over_billed, progress, take)
      left[progress] -= take
      others_cap -= take
    end
    credits.each_with_index.map { |attributes, position| attributes.merge(position:) }
  end

  # --- What's left to bill as progress ----------------------------------------------------

  # A job line: its subtotal less progress on it, nothing once it has a final bill; never more
  # than what's left of its quote line.
  def left_cents(line)
    case line
    when JobLineItem
      job = @jobs_by_id[line.job_id]
      return 0 if billed_job_line_ids.include?(line.id) || job.nil? || job.status == "cancelled"

      own = self.class.subtotal_cents(line) - held(@progress.select { _1.job_line_item_id == line.id })
      quote_line = @quote_lines[line.claim&.quote_line_item_id]
      [ own, (left_cents(quote_line) if quote_line) ].compact.min.clamp(0..)
    when QuoteLineItem
      billed = @finals.select { _1.quote_line_item_id == line.id }.sum { self.class.subtotal_cents(_1) }
      (kept_value_cents(line) - billed - held(@progress.select { _1.quote_line_item_id == line.id })).clamp(0..)
    end
  end

  # --- Discount shares ---------------------------------------------------------------------

  # S: each quote line's kept value after its discount. `current` adds this invoice's final bills.
  def discount_base_cents(current: []) = @quote_lines.values.sum { kept_value_cents(_1, current:) }

  def kept_value_cents(line, current: [])
    billed = (@finals + current).select { _1.final && _1.quote_line_item_id == line.id }
    billed_ids = billed.filter_map(&:job_line_item_id)
    completed = live_job_lines(line).select { @jobs_by_id[_1.job_id].status == "completed" && !billed_ids.include?(_1.id) }
    rest = [ line.quantity.to_d - (billed + completed).sum { _1.quantity.to_d }, 0 ].max
    gross = (billed + completed).sum(&:line_amount_cents) + (rest * line.unit_price_cents.to_i).round(0, Money::ROUNDING).to_i
    off = case line.discount_kind
    when "percent" then (gross * line.discount_percent.to_d / 100).round(0, Money::ROUNDING).to_i
    when "amount" then line.discount_amount_cents.to_i
    else 0
    end
    (gross - off.clamp(0, gross)).clamp(0..)
  end

  # A quote line's fixed discount d over quantity q, for this invoice's bills of it:
  # min(d, round(d × quantity billed ÷ q)) less what earlier bills of it took.
  def line_share_cents(line, current)
    return 0 unless shares? && line.discount_kind == "amount" && line.quantity.to_d.positive?

    earlier = sent_finals.select { _1.quote_line_item_id == line.id }
    quantity = (earlier + current).sum { _1.quantity.to_d }
    target = [ line.discount_amount_cents.to_i, round(line.discount_amount_cents.to_i * quantity / line.quantity.to_d) ].min
    (target - earlier.sum(&:discount_share_cents)).clamp(0..)
  end

  # The quote's fixed discount D: target = min(D, round(D × W ÷ S)), less the shares on other
  # invoices that went out, from zero up to this invoice's quote work (the cap's hold-back falls
  # into the next target).
  def quote_share_cents(current)
    total = quote&.discount_kind == "amount" ? quote.discount_amount_cents.to_i : 0
    return 0 unless shares? && total.positive?

    work = current.select { _1.final && _1.quote_line_item_id }
    base = discount_base_cents(current: work)
    return 0 unless base.positive?

    billed = (sent_finals.select(&:quote_line_item_id) + work).sum { self.class.subtotal_cents(_1) }
    target = [ total, round(total * billed / base.to_d) ].min
    others = Invoice.where(quote_id: quote.id).where.not(sent_at: nil).where.not(status: "void").where.not(id: @except_id).sum(:quote_discount_share_cents)
    (target - others).clamp(0, work.sum { self.class.subtotal_cents(_1) })
  end

  # Recurring quotes don't share (JOB-10).
  def shares? = quote.present? && !quote.recurring?

  # --- Summaries for the quote and job pages ----------------------------------------------

  # { billed:, credited:, over_billed: } in cents, for the quote, or only a job's own lines.
  def summary(job: nil)
    lines = job ? @progress.select { (jl = @job_lines[_1.job_line_item_id]) && jl.job_id == job.id } : @progress
    sent = lines.select { _1.invoice.sent_at }
    { billed: sent.sum { amount_cents(_1) }, credited: sent.sum { @used.fetch(_1.id, 0) },
      over_billed: (over_billed & lines).sum { remaining_cents(_1) } }
  end

  private

  def credit(kind, progress, amount)
    { kind: kind.to_s, source_invoice_id: progress.invoice_id, source_line_item_id: progress.id, amount_cents: amount, sign: -1,
      tax_rates: (progress.taxable ? progress.tax_rates || progress.invoice.tax_rates : []) }
  end

  # Progress held on a line: what's on invoices that aren't void, less what's been credited.
  def held(lines) = lines.sum { [ amount_cents(_1) - @used.fetch(_1.id, 0), 0 ].max }

  def billed_job_line_ids = @billed_job_line_ids ||= @finals.filter_map(&:job_line_item_id).to_set

  def sent_finals = @sent_finals ||= @finals.select { _1.invoice.sent_at }

  # The job lines on live jobs doing this quote line.
  def live_job_lines(line) = @job_lines.values.select { _1.claim&.quote_line_item_id == line.id && @jobs_by_id[_1.job_id].status != "cancelled" }

  def round(value) = value.to_d.round(0, Money::ROUNDING).to_i
end
