# PAY-08: what's been billed of a quote's work (or of a job without a quote), read once under
# PAY-06's lock: final bills, progress billed before the work was done, and what's been credited.
# Progress and credits are what the progress invoice charged for a line, net of its discounts
# (the quote's percent, any typed on it) and before tax: discounts on a progress invoice apply
# to the cash collected on it, and a final bill deducts only that net amount (owner, 2026-11-23).
# What's left of a line to bill is measured in line subtotals (before an invoice's discount).
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
    bills = InvoiceLineItem.where.not(invoice_status: "void").includes(invoice: %i[line_items revisions]) # what each charged, without a query per invoice
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
  def self.subtotal_cents(line, currency = line.document_currency) = Pricing::DocumentTotals.new(currency:, lines: [ line.to_pricing([]) ]).lines.first.subtotal.cents

  # --- Progress and credits ---------------------------------------------------------------

  # What its invoice charged for a progress line, net of that invoice's discounts, before tax.
  # While it's being revised, what the version the client was sent charged (owner, 2026-11-23:
  # credits follow the money charged, never an unsent change).
  def amount_cents(progress_line) = charged(progress_line.invoice).fetch(progress_line.key, 0)

  # The tax rates a progress line was charged at, which its credits use.
  def rates_of(progress_line)
    return [] unless progress_line.taxable

    progress_line.own_tax_rate_list || progress_line.invoice.tax_rate_list
  end

  # What the client paid for these cents of a progress line: with its tax (already in a
  # tax-inclusive price), each rate rounded.
  def with_tax_cents(cents, progress_line)
    return cents if progress_line.invoice.prices_include_tax

    cents + rates_of(progress_line).sum { (cents * _1.percent / 100).round(0, Money::ROUNDING).to_i }
  end

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

  # Nothing left to bill: a job line with a final bill that went out (or on a cancelled job); a
  # quote line with nothing to do whose live claims are all billed so, direct bills included.
  # `billed` adds this invoice's final bills. (A draft's final bill is still to come: it credits
  # the progress when it's sent.)
  def nothing_left?(home, billed: [])
    kind, id = home
    billed_ids = sent_finals.filter_map(&:job_line_item_id).to_set + billed.filter_map(&:job_line_item_id)
    if kind == :job
      job_line = @job_lines[id]
      return job_line.nil? || billed_ids.include?(id) || @jobs_by_id[job_line.job_id].status == "cancelled"
    end
    line = @quote_lines[id] or return true
    line.to_do_quantity <= 0 && live_job_lines(line).all? { billed_ids.include?(_1.id) } &&
      @finals.select { _1.quote_line_item_id == id && _1.job_line_item_id.nil? }.all? { _1.invoice.sent_at }
  end

  def over_billed_cents(billed: []) = over_billed(billed:).sum { remaining_cents(_1) }

  # Progress lines whose home has nothing left to bill, with something not yet credited.
  def over_billed(billed: [])
    @progress.select { remaining_cents(_1).positive? && (home = home(_1)) && nothing_left?(home, billed:) }
  end

  # Credits for an invoice's final bills: [[line, cap_cents]] in order, each cap what this bill
  # takes for the line after its discount share. Each line takes min(progress not yet credited,
  # what's left of its cap): its job line's own first, then its quote line's. Then over-billing,
  # up to what's left of the invoice. `bases` ({ tax rate => cents }) is what each rate is charged
  # on: a credit never takes one below zero, so tax and the total stay at zero or more; what it
  # can't take stays over-billed for the next invoice. Returns attributes for InvoiceCredit.
  # A line's progress is credited only at the tax rates it was charged at (BillingCredits refuses
  # a bill whose line is taxed otherwise), so a credit always equals what was charged.
  def credits_for(lines_with_caps, others_cap: 0, bases: {})
    left = Hash.new { |hash, line| hash[line] = remaining_cents(line) }
    bases = Hash.new(0).merge(bases)
    credits = []
    take = lambda do |kind, progress, cap|
      rates = rates_of(progress)
      amount = [ left[progress], cap, *rates.map { bases[_1] } ].min
      next 0 unless amount.positive?

      credits << credit(kind, progress, amount)
      left[progress] -= amount
      rates.each { bases[_1] -= amount }
      amount
    end
    lines_with_caps.each do |line, cap, rates|
      pools_of(line).each { cap -= take.(:progress, _1, cap) if rates.nil? || rates_of(_1).to_set == rates.to_set }
      others_cap += cap
    end
    over_billed(billed: lines_with_caps.map(&:first)).each { others_cap -= take.(:over_billed, _1, others_cap) }
    credits.each_with_index.map { |attributes, position| attributes.merge(position:) }
  end

  # The progress a final bill would credit: its job line's, then its quote line's.
  def pools_of(line) = [ home(line), ([ :quote, line.quote_line_item_id ] if line.quote_line_item_id) ].compact.uniq.flat_map { pool(_1) }

  # --- What's left to bill as progress ----------------------------------------------------

  # What's left of a line to bill as progress, net: what the final would charge for the rest of it
  # after the discount it will apply (the quote's percent or its expected share of a fixed one, a
  # lone job's own), less progress held on it. A progress invoice never charges a line more than
  # the final would (owner, 2026-11-23): with $100 off $1,000, at most $900 goes up front. A job
  # line has nothing left once it has a final bill, and never more than its quote line.
  def left_cents(line)
    case line
    when JobLineItem
      job = @jobs_by_id[line.job_id]
      return 0 if billed_job_line_ids.include?(line.id) || job.nil? || job.status == "cancelled"

      quote_line = @quote_lines[line.claim&.quote_line_item_id]
      own = after_discounts(subtotal(line) - expected_line_share(line, quote_line), job) - held(@progress.select { _1.job_line_item_id == line.id })
      [ own, (left_cents(quote_line) if quote_line) ].compact.min.clamp(0..)
    when QuoteLineItem
      billed = @finals.select { _1.quote_line_item_id == line.id }.sum { subtotal(_1) }
      (after_discounts(kept_value_cents(line) - billed) - held(@progress.select { _1.quote_line_item_id == line.id })).clamp(0..)
    end
  end

  # A job line's expected part of its quote line's fixed discount d: d × its quantity ÷ the line's.
  def expected_line_share(job_line, quote_line)
    return 0 unless shares? && quote_line&.discount_kind == "amount" && quote_line.quantity.to_d.positive?

    [ round(quote_line.discount_amount_cents.to_i * job_line.quantity.to_d / quote_line.quantity.to_d), quote_line.discount_amount_cents.to_i ].min
  end

  # The invoices holding a line's final bills (drafts too), which leave nothing to bill as progress.
  def final_invoices(work)
    key = work.is_a?(JobLineItem) ? :job_line_item_id : :quote_line_item_id
    @finals.select { _1.public_send(key) == work.id }.map(&:invoice).uniq
  end

  # Line subtotal cents after the document discount the final will apply.
  def after_discounts(cents, job = nil)
    return cents unless cents.positive?

    document = quote || job
    case document&.discount_kind
    when "percent" then round(cents * (100 - document.discount_percent.to_d) / 100)
    when "amount" then quote ? after_share(cents) : lone_job_share(cents, job)
    else cents
    end
  end

  # A job without a quote keeps its own fixed discount D: × (its subtotal − D) ÷ its subtotal.
  def lone_job_share(cents, job)
    base = job.line_items.sum { subtotal(_1) }
    base.positive? ? round(cents * [ base - job.discount_amount_cents.to_i, 0 ].max / base.to_d) : cents
  end

  # Cents of quote work less their expected share of a fixed quote discount D: × (S − D) ÷ S.
  def after_share(cents)
    total = shares? && quote.discount_kind == "amount" ? quote.discount_amount_cents.to_i : 0
    return cents unless total.positive? && cents.positive?

    base = (@base ||= discount_base_cents)
    base.positive? ? round(cents * [ base - total, 0 ].max / base.to_d) : cents
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

    billed = (sent_finals.select(&:quote_line_item_id) + work).sum { subtotal(_1) }
    target = [ total, round(total * billed / base.to_d) ].min
    others = Invoice.where(quote_id: quote.id).where.not(sent_at: nil).where.not(status: "void").where.not(id: @except_id).sum(:quote_discount_share_cents)
    (target - others).clamp(0, work.sum { subtotal(_1) })
  end

  # Recurring quotes don't share (JOB-10).
  def shares? = quote.present? && !quote.recurring?

  # --- Summaries for the quote and job pages ----------------------------------------------

  # { billed:, credited:, over_billed: } in cents with tax, as the client was charged, for the
  # quote, or only a job's own lines.
  def summary(job: nil)
    lines = job ? @progress.select { (jl = @job_lines[_1.job_line_item_id]) && jl.job_id == job.id } : @progress
    sent = lines.select { _1.invoice.sent_at }
    { billed: sent.sum { with_tax_cents(amount_cents(_1), _1) }, credited: sent.sum { with_tax_cents(@used.fetch(_1.id, 0), _1) },
      over_billed: (over_billed & lines).sum { with_tax_cents(remaining_cents(_1), _1) } }
  end

  private

  def credit(kind, progress, amount)
    { kind: kind.to_s, source_invoice_id: progress.invoice_id, source_line_item_id: progress.id, amount_cents: amount,
      tax_rates: (progress.taxable ? progress.tax_rates || progress.invoice.tax_rates : []) }
  end

  # A line's subtotal in its document's currency, without loading its document again.
  def subtotal(line)
    currency = case line
    when JobLineItem then @jobs_by_id[line.job_id]&.currency
    when InvoiceLineItem then line.invoice.currency
    else quote&.currency
    end
    self.class.subtotal_cents(line, currency || line.document_currency)
  end

  # Progress held on a line, net: what's on invoices that aren't void, less what's been credited.
  def held(lines) = lines.sum { [ amount_cents(_1) - @used.fetch(_1.id, 0), 0 ].max }

  # { line key => net charged } for an invoice: the version the client was sent while it's being
  # revised (Invoice#charged_by_key).
  def charged(invoice) = (@charged ||= {})[invoice.id] ||= invoice.charged_by_key

  def billed_job_line_ids = @billed_job_line_ids ||= @finals.filter_map(&:job_line_item_id).to_set

  def sent_finals = @sent_finals ||= @finals.select { _1.invoice.sent_at }

  # The job lines on live jobs doing this quote line.
  def live_job_lines(line) = @job_lines.values.select { _1.claim&.quote_line_item_id == line.id && @jobs_by_id[_1.job_id].status != "cancelled" }

  def round(value) = value.to_d.round(0, Money::ROUNDING).to_i
end
