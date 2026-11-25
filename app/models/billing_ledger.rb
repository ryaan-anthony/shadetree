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
  attr_reader :quote, :jobs, :progress, :finals

  def initialize(quote: nil, job: nil, except: nil, current: [])
    @quote = quote
    @current = current # the excepted invoice's lines: its direct bills are work done, for a shortfall
    @jobs = quote ? quote.jobs.to_a : [ job ]
    @except_id = except&.id
    @quote_lines = (quote ? quote.line_items.to_a : []).index_by(&:id)
    @jobs_by_id = @jobs.index_by(&:id)
    @job_lines = JobLineItem.where(job_id: @jobs_by_id.keys).includes(:claim).order(:id).to_a.index_by(&:id)
    bills = InvoiceLineItem.where.not(invoice_status: "void").includes(invoice: %i[line_items revisions]) # what each charged, without a query per invoice
                           .where("invoice_line_items.job_line_item_id IN (:jobs) OR invoice_line_items.quote_line_item_id IN (:quotes)",
                                  jobs: @job_lines.keys.presence || [ 0 ], quotes: @quote_lines.keys.presence || [ 0 ])
    bills = bills.where.not(invoice_id: @except_id) if @except_id
    @finals, @progress = bills.order(:id).to_a.partition(&:final)
    # In the order they went out, drafts last (a fixed key: never the clock, which would follow the
    # order rows happen to come back in).
    @progress.sort_by! { [ _1.invoice.sent_at ? 0 : 1, _1.invoice.sent_at || Time.at(0), _1.invoice_id, _1.position, _1.id ] }
    @used = InvoiceCredit.counted.where(source_line_item_id: @progress.map(&:id)).where.not(invoice_id: @except_id)
                         .group(:source_line_item_id).sum(:amount_cents)
  end

  def quote_line(id) = @quote_lines[id]
  def job_line(id) = @job_lines[id]

  # Done: nothing to do and every live job on it completed (progress billing is for work not done).
  def done?(line) = line.to_do_quantity <= 0 && live_job_lines(line).all? { @jobs_by_id[_1.job_id].status == "completed" }

  def self.for(invoice) = new(quote: invoice.quote, job: (invoice.job unless invoice.quote), except: invoice, current: invoice.current_line_items)

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
  # `taken` ({ line => cents }) gathers what each final bill's own progress credits take.
  def credits_for(lines_with_caps, others_cap: 0, bases: {}, taken: Hash.new(0), tax_room: {})
    @tax_credited = taxes_credited.dup # what each progress invoice's credits have taken, per rate, so far
    @tax_carried = taxes_carried.dup # and the tax they carry
    @tax_room = tax_room.dup # the tax this invoice charges, per rate, for its credits to carry
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
      pools_of(line).each do |progress|
        next unless rates.nil? || rates_of(progress).to_set == rates.to_set

        amount = take.(:progress, progress, cap)
        cap -= amount
        taken[line] += amount
      end
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

    round(line_parts.fetch(line.id, 0) * fraction * (@outstanding ||= outstanding_cents) / total.to_d)
  end

  # Cents split by weight, each part rounded down, the cents left going to the largest remainders
  # (ties in order), so the parts add up exactly: { key => weight } to { key => cents }.
  def self.largest_remainder(cents, weights)
    total = weights.values.sum
    return weights.transform_values { 0 } unless total.positive?

    exact = weights.transform_values { cents * _1.to_d / total }
    parts = exact.transform_values(&:floor)
    (cents - parts.values.sum).times.zip(exact.sort_by.with_index { |(_, value), i| [ -(value - value.floor), i ] }) { |_, (key, _)| parts[key] += 1 }
    parts
  end

  # Tax rates as a key: the same rates in any order are one group.
  def self.group(rates) = rates.sort_by { [ _1.name, _1.percent ] }

  # The quote's discount by what its lines carry, taxed or not: { group => cents }, in the same
  # proportions as the quote spreads it (scaled for a shortfall), so invoices' tax adds up to the
  # quote's where the work is taxed as quoted (owner, 2026-11-23).
  def discount_mix
    @discount_mix ||= Hash.new(0).merge(scaled_mix)
  end

  # The full mix ({ group => cents } as the quote spreads D), scaled for a shortfall: D' spread by
  # largest remainder, no group above its full part (a group done in full keeps all of its part).
  def scaled_mix
    return {} unless quote_discount_cents.positive?

    full = line_parts.each_with_object(Hash.new(0)) { |(id, cents), mix| mix[group_of(@quote_lines[id])] += cents }
    weights = line_parts.each_with_object(Hash.new(0)) { |(id, cents), mix| mix[group_of(@quote_lines[id])] += cents * done_fraction(@quote_lines[id]) }
    parts = self.class.largest_remainder(quote_discount_cents, weights.transform_values { [ _1, 0 ].max })
    over = parts.sum { |group, cents| [ cents - full[group], 0 ].max }
    return parts unless over.positive?

    parts = parts.to_h { |group, cents| [ group, [ cents, full[group] ].min ] }
    room = parts.to_h { |group, cents| [ group, full[group] - cents ] }.select { _2.positive? }
    self.class.largest_remainder(over, room).each { |group, cents| parts[group] += cents }
    parts
  end

  # What a line carries of the quote's discount, taxed or not: the quote's tax rates or none. A job
  # taxed otherwise still counts as the quote's: its discount comes off those lines, at their
  # rates (owner, 2026-11-23).
  def group_of(line) = line&.taxable ? self.class.group(quote.tax_rate_list) : []

  # A progress line's group, by its id (for a credit).
  def progress_group(id) = group_of(@progress.find { _1.id == id })

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
  # becomes its amount). None for a recurring quote (JOB-10) or a job without a quote. Once its work
  # is all done with less than quoted (a shortfall), it scales to the quoted value done: D × that
  # ÷ the quote's value, rounded once (owner, 2026-11-23), and `discount_mix` spreads it by largest
  # remainder; the rest is `unused_discount_cents`.
  def quote_discount_cents
    @quote_discount_cents ||= if all_done? && full_quote_discount_cents.positive?
      values = quote.line_items.to_a.zip(quote.totals.lines).map { |item, result| [ result.subtotal.cents, done_fraction(item) ] }
      whole = values.sum(&:first)
      whole.positive? ? round(full_quote_discount_cents * values.sum { _1 * _2 } / whole.to_d) : 0
    else
      full_quote_discount_cents
    end
  end

  def full_quote_discount_cents
    return 0 unless shares? && quote.discount_kind.in?(%w[amount percent])

    @full_quote_discount_cents ||= quote.totals.discount.cents
  end

  # The quote's discount a shortfall leaves unused: shown as "not used", never outstanding.
  def unused_discount_cents = full_quote_discount_cents - quote_discount_cents

  # A shortfall is final once the quote's work is all done: nothing to do, and every job on it
  # completed or cancelled (what's left is billed, or nothing is).
  def all_done?
    return @all_done if defined?(@all_done)

    @all_done = quote.present? && @quote_lines.values.none? { _1.to_do_quantity.positive? } && @jobs.all? { _1.status.in?(%w[completed cancelled]) }
  end

  # How much of a quote line was done (billed, or completed to bill), at most all of it: 1 till the
  # work is all done.
  def done_fraction(line)
    return 1 unless all_done? && line && line.quantity.to_d.positive?

    direct = (@finals + @current.select(&:final)).select { _1.quote_line_item_id == line.id && _1.job_line_item_id.nil? }
    done = live_job_lines(line).sum { _1.quantity.to_d } + direct.sum { _1.quantity.to_d }
    (done / line.quantity.to_d).clamp(0, 1)
  end

  # What's left of it: D less what work invoices that aren't void apply (drafts hold theirs). What
  # a progress invoice applies only lowers the cash it collects: its final bill credits the net it
  # charged, so the work's invoices still give the whole discount (owner, 2026-11-23).
  def outstanding_cents = [ net_outstanding_cents, 0 ].max

  # The same, unclamped: below zero once a shortfall scaled the discount under what was applied
  # (the last invoice charges that back). What a last invoice couldn't take is owed: given.
  def net_outstanding_cents = quote_discount_cents - earlier_parts.sum { _1["cents"].to_i }

  # What other work invoices applied, by group and by the rates it came off: { group => { rates => cents } }.
  def applied_by_group
    earlier_parts.reject { _1["owed"] }.each_with_object(Hash.new { |hash, key| hash[key] = Hash.new(0) }) do |part, sums|
      sums[self.class.group(self.class.rates_from(part["from"] || part["rates"]))][self.class.group(self.class.rates_from(part["rates"]))] += part["cents"].to_i
    end
  end

  # What's left of the discount by tax group: the quote's mix less what other work invoices that
  # aren't void counted against each group (a part's `from`).
  def outstanding_by_group = fit_outstanding(net_outstanding_by_group.transform_values { [ _1, 0 ].max })

  # Unclamped: a group below zero took more than its scaled part.
  def net_outstanding_by_group
    left = Hash.new(0).merge(discount_mix)
    earlier_parts.each { |part| left[self.class.group(self.class.rates_from(part["from"] || part["rates"]))] -= part["cents"].to_i }
    left
  end

  # What a last invoice couldn't take of the scaled discount: a credit owed to the client, tracked
  # as over-billed (owner, 2026-11-24). With tax at its rates: what the client paid on it.
  def discount_owed_cents(with_tax: false, sent: false)
    parts = sent ? work_invoices.where.not(sent_at: nil).order(:id).pluck(:quote_discount_parts).flatten : earlier_parts
    parts.select { _1["owed"] }.sum do |part|
      cents = part["cents"].to_i
      with_tax ? cents + self.class.rates_from(part["rates"]).sum { (cents * _1.percent / 100).round(0, Money::ROUNDING).to_i } : cents
    end
  end

  def fit_outstanding(left)
    total = outstanding_cents
    return Hash.new(0).merge(left) if left.values.sum <= total
    return Hash.new(0) if total.zero?

    # A group took more than its part (a shortfall scaled it after): the rest shares what's left.
    Hash.new(0).merge(self.class.largest_remainder(total, left))
  end

  # B11: progress can't be billed once the work left, less progress not yet credited, can't take
  # the quote's discount left: any progress charge would leave too little.
  def progress_blocked? = quote.present? && outstanding_cents.positive? && work_left_cents - uncredited_cents - outstanding_cents <= 0

  # Whether progress has anything to bill: a line of the job (or the quote) with something left,
  # after progress already on invoices, drafts included.
  def progress_left?(job: nil)
    lines = job ? @job_lines.values.select { _1.job_id == job.id } : @quote_lines.values.reject { done?(_1) }
    lines.any? { left_cents(_1).positive? }
  end

  PROGRESS_BLOCKED = "Nothing is left to bill as progress: the work left is needed for the quote's discount."

  def self.rates_from(list) = Array(list).map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

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
      left[group_of(line)] += subtotal(line) - expected_line_share(line, @quote_lines[line.claim&.quote_line_item_id])
    end
    # A line billed directly on this invoice claims its work when it's saved: it isn't to do.
    direct = billed.select { _1.new_record? && _1.job_line_item_id.nil? && _1.quote_line_item_id }.group_by(&:quote_line_item_id)
    @quote_lines.each_value do |line|
      left[group_of(line)] += to_do_value(line, less: direct.fetch(line.id, []).sum { |item| item.quantity.to_d })
    end
    left
  end

  # Progress charged and not yet credited, on invoices that went out: what later final bills must
  # still take off. (A progress draft isn't charged yet: it's checked against what's left when
  # it's sent.)
  def uncredited_cents = @progress.sum { remaining_cents(_1) }

  # The same, by group (taxed or not).
  def uncredited_by_group = @progress.each_with_object(Hash.new(0)) { |line, sums| sums[group_of(line)] += remaining_cents(line) }

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

  # A quote line's percent discount, shared out the same way (B16, owner, 2026-11-24): each bill's
  # share is round(percent × gross billed so far on the line) less what earlier bills of it took,
  # so a line's bills add up to the discount on its whole quantity whichever way it's split (rounded
  # per job line, they could be a cent out). Returns one share per bill in `current`; a bill whose
  # job line carries another percent keeps its own discount and takes none.
  def percent_shares(line, current)
    return current.map { 0 } unless shares? && line.discount_kind == "percent"

    earlier = sent_finals.select { _1.quote_line_item_id == line.id && percent_bill?(line, _1) }
    gross = earlier.sum(&:line_amount_cents)
    given = earlier.sum(&:discount_share_cents)
    current.map do |item|
      next 0 unless percent_bill?(line, item)

      gross += item.line_amount_cents
      share = (round(gross * line.discount_percent.to_d / 100) - given).clamp(0..[ item.line_amount_cents, 0 ].max)
      given += share
      share
    end
  end

  # Whether a bill of this quote line takes the quote line's percent as a share: its job line
  # carries that percent (a direct bill copies it).
  def percent_bill?(line, item)
    return true unless item.job_line_item_id

    job_line = @job_lines[item.job_line_item_id]
    job_line.nil? || (job_line.discount_kind == "percent" && job_line.discount_percent.to_d == line.discount_percent.to_d)
  end

  # Recurring quotes don't share (JOB-10).
  def shares? = quote.present? && !quote.recurring?

  # --- Summaries for the quote and job pages ----------------------------------------------

  # { billed:, credited:, over_billed:, owed: } in cents with tax, as the client was charged, for
  # the quote, or only a job's own lines. Over-billing is credited on the next invoice while there's
  # work left to bill; once there's none, it's owed to the client, as is what a last invoice
  # couldn't take of a scaled discount (owner, 2026-11-24). Nothing credits that: staff refund it.
  # With tax as charged (B14): a line's share of its invoice's tax at each rate (largest
  # remainder, so an invoice's lines add up to what it charged), and each credit's tax as stored.
  def summary(job: nil)
    lines = job ? @progress.select { (jl = @job_lines[_1.job_line_item_id]) && jl.job_id == job.id } : @progress
    sent = lines.select { _1.invoice.sent_at }
    over = (over_billed & lines).sum { charged_with_tax(_1) - credited_with_tax(_1) }
    owed = job ? 0 : discount_owed_cents(with_tax: true, sent: true)
    over, owed = 0, owed + over if nothing_left_to_bill?
    { billed: sent.sum { charged_with_tax(_1) }, credited: sent.sum { credited_with_tax(_1) }, over_billed: over, owed: }
  end

  # What a progress line charged, with its share of its invoice's tax.
  def charged_with_tax(line)
    return amount_cents(line) if line.invoice.prices_include_tax

    amount_cents(line) + charged_taxes(line.invoice).sum do |rate, tax|
      lines = @progress.select { _1.invoice_id == line.invoice_id && rates_of(_1).include?(rate) }
      lines.include?(line) ? self.class.largest_remainder(tax, lines.to_h { [ _1, amount_cents(_1) ] })[line] : 0
    end
  end

  # What's been credited of a progress line, with the tax each credit carries.
  def credited_with_tax(line) = @used.fetch(line.id, 0) + (line.invoice.prices_include_tax ? 0 : used_tax.fetch(line.id, 0))

  def used_tax
    @used_tax ||= InvoiceCredit.counted.where(source_line_item_id: @progress.map(&:id)).where.not(invoice_id: @except_id)
                               .pluck(:source_line_item_id, :tax_charged).each_with_object(Hash.new(0)) { |(id, taxes), sums| sums[id] += taxes.sum { _1["cents"].to_i } }
  end

  # No work is left to bill, so no later invoice can credit anything: every live job line billed
  # and nothing to do.
  def nothing_left_to_bill? = finishes?([]) && @quote_lines.values.none? { _1.to_do_quantity.positive? }

  private

  def credit(kind, progress, amount)
    { kind: kind.to_s, source_invoice_id: progress.invoice_id, source_line_item_id: progress.id, amount_cents: amount,
      tax_rates: (progress.taxable ? progress.tax_rates || progress.invoice.tax_rates : []), tax_charged: credit_tax(progress, amount) }
  end

  # B14: the tax a credit carries at each rate, as its progress invoice charged it. That invoice's
  # tax at a rate, T on a base B (what its lines at that rate charged), goes to its credits in step
  # with what they've taken: round(T × after ÷ B) − round(T × before ÷ B). So once all of it is
  # credited, its credits carry exactly the T it charged, however they're split.
  def credit_tax(progress, amount)
    invoice = progress.invoice
    taxes = charged_taxes(invoice)
    rates_of(progress).filter_map do |rate|
      base = @progress.select { _1.invoice_id == invoice.id && rates_of(_1).include?(rate) }.sum { amount_cents(_1) }
      tax = taxes.fetch(rate, 0)
      before = @tax_credited[[ invoice.id, rate ]]
      # What all its credits so far should carry, less what they do: a credit that couldn't carry
      # its share (the invoice crediting it charges less tax) leaves it to the next one.
      owed = base.positive? ? round(tax * (before + amount) / base.to_d) - @tax_carried[[ invoice.id, rate ]] : 0
      cents = owed.clamp(0..[ @tax_room.fetch(rate, 0), 0 ].max)
      @tax_room[rate] = @tax_room.fetch(rate, 0) - cents
      @tax_carried[[ invoice.id, rate ]] += cents
      @tax_credited[[ invoice.id, rate ]] += amount
      { "name" => rate.name, "percent" => rate.percent.to_d.to_s("F"), "cents" => cents }
    end
  end

  # { rate => cents } a progress invoice charged in tax (the version the client has).
  def charged_taxes(invoice) = (@charged_taxes ||= {})[invoice.id] ||= invoice.charged_tax_by_rate

  # What credits that went out (on other invoices) have taken of each progress invoice, per rate.
  def taxes_credited
    @taxes_credited ||= InvoiceCredit.counted.where(source_invoice_id: @progress.map(&:invoice_id).uniq).where.not(invoice_id: @except_id)
                                     .pluck(:source_invoice_id, :amount_cents, :tax_rates)
                                     .each_with_object(Hash.new(0)) { |(id, cents, rates), sums| self.class.rates_from(rates).each { sums[[ id, _1 ]] += cents } }
  end

  # What credits that went out (on other invoices) carry of each progress invoice's tax, per rate.
  def taxes_carried
    @taxes_carried ||= InvoiceCredit.counted.where(source_invoice_id: @progress.map(&:invoice_id).uniq).where.not(invoice_id: @except_id)
                                    .pluck(:source_invoice_id, :tax_charged).each_with_object(Hash.new(0)) do |(id, taxes), sums|
      taxes.each { sums[[ id, Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) ]] += _1["cents"].to_i }
    end
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

  def work_invoices = Invoice.where(quote_id: quote&.id, kind: "work").where.not(status: "void").where.not(id: @except_id)

  def earlier_parts = @earlier_parts ||= work_invoices.order(:id).pluck(:quote_discount_parts).flatten

  # Each quote line's part of the quote's discount, as the quote spreads it.
  def line_parts = @line_parts ||= quote.line_items.to_a.zip(quote.totals.lines).to_h { |item, result| [ item.id, (result.subtotal - result.taxable).cents ] }
end
