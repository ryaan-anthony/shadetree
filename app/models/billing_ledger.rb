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
# - The quote's discount is applied as staff choose on each invoice (owner, 2026-11-23):
#   outstanding_cents, work_left_cents and uncredited_cents give the range BillingCredits holds
#   the choice to. A line's fixed discount stays shared by quantity billed (line_share_cents).
#
#   ledger = BillingLedger.new(quote:, except: invoice)
#   ledger.over_billed_cents, ledger.left_cents(job_line), ledger.outstanding_cents
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
      own = after_discounts(subtotal(line) - expected_line_share(line, quote_line), job) - held(@progress.select { _1.job_line_item_id == line.id }) -
            (quote_line ? discount_left_part(quote_line, line.quantity.to_d / [ quote_line.quantity.to_d, 1 ].max) : 0)
      [ own, (left_cents(quote_line) if quote_line) ].compact.min.clamp(0..)
    when QuoteLineItem
      billed = @finals.select { _1.quote_line_item_id == line.id }.sum { subtotal(_1) }
      (after_discounts(kept_value_cents(line) - billed) - held(@progress.select { _1.quote_line_item_id == line.id }) - discount_left_part(line)).clamp(0..)
    end
  end

  # A quote line's part of the quote's discount still to come (its share of D, as the quote spreads
  # it, scaled by what's outstanding): progress leaves it for the final (owner, 2026-11-23).
  def discount_left_part(line, fraction = 1)
    total = quote_discount_cents
    return 0 unless total.positive?

    @line_parts ||= quote.line_items.to_a.zip(quote.totals.lines).to_h { |item, result| [ item.id, (result.subtotal - result.taxable).cents ] }
    round(@line_parts.fetch(line.id, 0) * fraction * (@outstanding ||= outstanding_cents) / total.to_d)
  end

  # Tax rates as a key: the same rates in any order are one group.
  def self.group(rates) = rates.sort_by { [ _1.name, _1.percent ] }

  # The quote's discount by the tax its lines carry: { rates => cents }, in the same proportions
  # as the quote spreads it, so invoices' tax adds up to the quote's (owner, 2026-11-23).
  def discount_mix
    return {} unless quote_discount_cents.positive?

    @discount_mix ||= quote.line_items.to_a.zip(quote.totals.lines).each_with_object(Hash.new(0)) do |(item, result), mix|
      mix[self.class.group(item.taxable ? quote.tax_rate_list : [])] += (result.subtotal - result.taxable).cents
    end
  end

  # A job line's expected part of its quote line's fixed discount d: d × its quantity ÷ the line's.
  def expected_line_share(job_line, quote_line)
    return 0 unless shares? && quote_line&.discount_kind == "amount" && quote_line.quantity.to_d.positive?

    [ round(quote_line.discount_amount_cents.to_i * job_line.quantity.to_d / quote_line.quantity.to_d), quote_line.discount_amount_cents.to_i ].min
  end

  # The live jobs doing a quote line, whose rates its final bills will be taxed at.
  def live_jobs_of(line) = live_job_lines(line).map { @jobs_by_id[_1.job_id] }.uniq

  # The invoices holding a line's final bills (drafts too), which leave nothing to bill as progress.
  def final_invoices(work)
    key = work.is_a?(JobLineItem) ? :job_line_item_id : :quote_line_item_id
    @finals.select { _1.public_send(key) == work.id }.map(&:invoice).uniq
  end

  # Line subtotal cents after the document discount the final will apply: a lone job's own. A
  # quote's discount is chosen per invoice (owner, 2026-11-23); what's still to come is held back
  # from progress as a whole (BillingCredits' minimum), not line by line.
  def after_discounts(cents, job = nil)
    return cents if quote || !cents.positive?

    case job&.discount_kind
    when "percent" then round(cents * (100 - job.discount_percent.to_d) / 100)
    when "amount" then lone_job_share(cents, job)
    else cents
    end
  end

  # --- The quote's discount, chosen per invoice (owner, 2026-11-23) ------------------------

  # D: the quote's discount in dollars, after line discounts, as the quote shows it (a percent
  # becomes its amount). None for a recurring quote (JOB-10) or a job without a quote.
  def quote_discount_cents
    return 0 unless shares? && quote.discount_kind.in?(%w[amount percent])

    @quote_discount_cents ||= quote.totals.discount.cents
  end

  # What's left of it: D less what work invoices that aren't void apply (drafts hold theirs). What
  # a progress invoice applies only lowers the cash it collects: its final bill credits the net it
  # charged, so the work's invoices still give the whole discount (owner, 2026-11-23).
  def outstanding_cents
    applied = Invoice.where(quote_id: quote&.id, kind: "work").where.not(status: "void").where.not(id: @except_id).sum(:quote_discount_share_cents)
    [ quote_discount_cents - applied, 0 ].max
  end

  # The quote's work still to bill after these final bills, after line discounts: lines on live
  # jobs without a final bill (added on site too) and what's still to do.
  def work_left_cents(billed: []) = work_left_by_group(billed:).values.sum

  # Whether billing these job lines (or, with none, the quote's to-do work directly) leaves no work
  # to bill: that invoice takes the whole of the quote's discount left.
  def finishes?(job_lines)
    ids = job_lines.map(&:id).to_set
    rest = @job_lines.values.reject { ids.include?(_1.id) || billed_job_line_ids.include?(_1.id) || @jobs_by_id[_1.job_id].status == "cancelled" }
    rest.empty? && (job_lines.any? ? @quote_lines.values.none? { _1.to_do_quantity.positive? } : true)
  end

  # The same, by the tax it will carry: { rates => cents }.
  def work_left_by_group(billed: [])
    billed_ids = billed_job_line_ids + billed.filter_map(&:job_line_item_id)
    left = Hash.new(0)
    @job_lines.values.select { @jobs_by_id[_1.job_id].status != "cancelled" && !billed_ids.include?(_1.id) }.each do |line|
      job = @jobs_by_id[line.job_id]
      left[self.class.group(line.taxable ? job.tax_rate_list : [])] += subtotal(line) - expected_line_share(line, @quote_lines[line.claim&.quote_line_item_id])
    end
    # A line billed directly on this invoice claims its work when it's saved: it isn't to do.
    direct = billed.select { _1.new_record? && _1.job_line_item_id.nil? && _1.quote_line_item_id }.group_by(&:quote_line_item_id)
    @quote_lines.each_value do |line|
      left[self.class.group(line.taxable ? quote.tax_rate_list : [])] += to_do_value(line, less: direct.fetch(line.id, []).sum { |item| item.quantity.to_d })
    end
    left
  end

  # Progress charged and not yet credited, on invoices that aren't void: what later final bills
  # must still take off.
  def uncredited_cents = held(@progress)

  # The same, by the tax it was charged at.
  def uncredited_by_group = @progress.each_with_object(Hash.new(0)) { |line, sums| sums[self.class.group(rates_of(line))] += held([ line ]) }

  def to_do_value(line, less: 0)
    quantity = line.to_do_quantity - less
    return 0 unless quantity.positive?

    gross = round(quantity * line.unit_price_cents.to_i)
    off = case line.discount_kind
    when "percent" then round(gross * line.discount_percent.to_d / 100)
    when "amount" then line.quantity.to_d.positive? ? round(line.discount_amount_cents.to_i * quantity / line.quantity.to_d) : 0
    else 0
    end
    [ gross - off, 0 ].max
  end

  # A job without a quote keeps its own fixed discount D: × (its subtotal − D) ÷ its subtotal.
  def lone_job_share(cents, job)
    base = job.line_items.sum { subtotal(_1) }
    base.positive? ? round(cents * [ base - job.discount_amount_cents.to_i, 0 ].max / base.to_d) : cents
  end

  # --- Discount shares ---------------------------------------------------------------------

  # A quote line's value after its discount: billed quantity at the price it was billed at,
  # completed at the job's, the rest at the current price (QTE-10).
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
