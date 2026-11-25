# PAY-06: an invoice bills completed work, and nothing is billed twice. A job's invoice bills its
# lines as done on the job (quantities confirmed at completion, its prices, lines added on site); a
# quote's bills every completed job's unbilled lines, and can be used again as more finish. A quote
# with no jobs (automatic jobs off, or every job cancelled) is billed directly from its lines.
#
# A line is billed once a final bill for it is on an invoice that isn't void (InvoiceLineItem
# .final_bills). Every billing path takes JOB-09's lock order (the quote, its jobs by id, the
# quote's lines by id; a job without a quote alone) and reads what's unbilled again under it; the
# database refuses a second final bill if anything gets past that.
#
# Behind split_jobs (JOB-09). With it off, billing works as before PAY-06: a job's invoice copies
# all its lines at any status, and a quote's bills the quote's lines as agreed; each line still
# links to what it bills and is the final bill only if there's none yet (repeats are progress).
module WorkBilling
  # Nothing to bill, or not yet: the message says why.
  class Refused < StandardError; end

  module_function

  def lock!(quote_id: nil, jobs: [])
    return QuoteWork.lock!(quote_id, jobs:) if quote_id

    Job.where(id: Array(jobs).map { _1.is_a?(Job) ? _1.id : _1 }).order(:id).lock.pluck(:id)
  end

  # Of these job lines, the ones with a final bill.
  def billed_job_line_ids(ids) = InvoiceLineItem.final_bills.where(job_line_item_id: ids).distinct.pluck(:job_line_item_id).to_set
  def billed_quote_line_ids(ids) = InvoiceLineItem.final_bills.where(job_line_item_id: nil, quote_line_item_id: ids).distinct.pluck(:quote_line_item_id).to_set

  # A job's completed work not billed yet: what its Create invoice and NTF-04 bill.
  def unbilled_lines(job)
    lines = job.line_items.to_a
    billed = billed_job_line_ids(lines.map(&:id))
    lines.reject { billed.include?(_1.id) }
  end

  # Which of these jobs are completed with something unbilled, in two queries however many there are
  # (the quote page lists them all).
  def billable_job_ids(jobs)
    completed = jobs.select { _1.status == "completed" }.map(&:id)
    return Set.new if completed.empty?

    lines = JobLineItem.where(job_id: completed).pluck(:id, :job_id)
    billed = billed_job_line_ids(lines.map(&:first))
    lines.reject { billed.include?(_1.first) }.to_set(&:last)
  end

  def billable?(job) = billable_job_ids([ job ]).include?(job.id)

  # A quote with no live job has work to bill directly: some line still to do with no direct bill.
  def directly_billable_lines(quote)
    lines = quote.line_items.to_a
    billed = billed_quote_line_ids(lines.map(&:id))
    lines.select { _1.to_do_quantity.positive? && !billed.include?(_1.id) }
  end

  # The job's Create invoice.
  # discount: "Apply now" for the quote's discount (dollars, "all" or blank; PAY-08).
  def bill_job!(job, by: nil, discount: nil)
    Invoice.transaction do
      lock!(quote_id: job.quote_id, jobs: [ job ])
      job.reload
      split = QuoteWork.split?(job.business)
      raise Refused, "#{job.number} isn't completed yet. An invoice bills completed work." if split && job.status != "completed"

      lines = split ? unbilled_lines(job) : job.line_items.to_a
      raise Refused, "Everything on #{job.number} is billed#{" (#{billed_on(job.line_items)})" if job.line_items.any?}." if lines.empty? && split
      check_priced!(lines)

      invoice = Invoice.new(client: job.client, property: job.property, job:, quote: job.quote, created_by: by, title: job.title, currency: job.currency)
      invoice.copy_pricing_from(job, lines: [])
      quote_discount_off!(invoice) if split
      add_job_lines(invoice, lines)
      invoice.quote_discount_applied = discount if split && invoice.quote_id
      invoice.save!
      invoice.record!(:created, by:, from: "job", number: job.number)
      invoice
    end
  end

  # The quote's Create invoice.
  def bill_quote!(quote, by: nil, discount: nil)
    Invoice.transaction do
      Quote.where(id: quote.id).lock.pluck(:id) # first, so the jobs read next can't change
      jobs = quote.jobs.where.not(status: "cancelled").order(:id).to_a
      lock!(quote_id: quote.id, jobs:)
      quote.reload
      raise Invoice::NotApproved, "Only an approved quote can be invoiced." unless quote.approved?

      invoice = if jobs.empty? then bill_directly(quote, by:, discount:)
      elsif QuoteWork.split?(quote.business) then bill_completed_jobs(quote, jobs, by:, discount:)
      else bill_as_agreed(quote, jobs.first, by:)
      end
      invoice.record!(:created, by:, from: "quote", number: quote.number)
      invoice
    end
  end

  # Each completed job's unbilled lines, in one invoice linked to the quote and every job. A line
  # keeps its job's tax rates where they differ from the first job's.
  def bill_completed_jobs(quote, jobs, by:, discount: nil)
    billing = jobs.select { _1.status == "completed" }.map { [ _1, unbilled_lines(_1) ] }.reject { _2.empty? }
    if billing.empty?
      unfinished = jobs.select(&:open?).map(&:number)
      raise Refused, unfinished.any? ? "Nothing on #{quote.number} is ready to bill: #{unfinished.to_sentence} #{unfinished.one? ? "isn't" : "aren't"} completed yet." : "Everything done on #{quote.number} is billed."
    end
    check_priced!(billing.flat_map(&:last))
    if billing.map { _1.first.prices_include_tax }.uniq.many?
      raise Refused, "#{billing.map { _1.first.number }.to_sentence} differ on whether prices include tax. Bill each from its own page."
    end

    first = billing.first.first
    invoice = Invoice.new(client: quote.client, property: quote.property, quote:, job: first, created_by: by, title: quote.title, currency: quote.currency,
                          tax_rates: first.tax_rates, prices_include_tax: first.prices_include_tax)
    invoice.jobs = billing.map(&:first)
    add_job_lines(invoice, billing.flat_map { |job, lines| lines.map { [ _1, (job.tax_rates if job.tax_rates != first.tax_rates) ] } })
    invoice.quote_discount_applied = discount
    invoice.save!
    invoice
  end

  # No live job: the quote's lines, as done and billed with no job, so no job can take them.
  # With split jobs, what's still to do of each; before, its lines in full (repeats are progress).
  def bill_directly(quote, by:, discount: nil)
    raise Refused, "#{quote.number} is recurring: each occurrence is billed from its own job." if quote.recurring?

    split = QuoteWork.split?(quote.business)
    rows = if split
      directly_billable_lines(quote).map { [ _1, _1.to_do_quantity, true ] }
    else # as before: every line in full, the final bill where there's none yet and work is free
      lines = quote.line_items.to_a
      billed = billed_quote_line_ids(lines.map(&:id))
      lines.map { [ _1, _1.quantity.to_d, !billed.include?(_1.id) && _1.to_do_quantity.positive? ] }
    end
    raise Refused, "Everything on #{quote.number} is billed." if split && rows.empty?

    invoice = Invoice.new(client: quote.client, property: quote.property, quote:, created_by: by, title: quote.title, currency: quote.currency)
    invoice.copy_pricing_from(quote, lines: [])
    quote_discount_off!(invoice) if split # PAY-08: fixed discounts come as shares
    items = invoice.sync_line_items(BuiltDocument.rows_from(rows.map(&:first)))
    items.zip(rows) do |item, (line, quantity, final)|
      item.assign_attributes(quantity:, quote_line_item_id: line.id, final:)
      item.set_discount(nil, nil) if split && item.discount_kind == "amount"
    end
    invoice.quote_discount_applied = discount if split
    invoice.save!
    invoice
  end

  # Before split jobs: the quote's lines as agreed, each linked to its job line.
  def bill_as_agreed(quote, job, by:)
    invoice = Invoice.new(client: quote.client, property: quote.property, quote:, job:, created_by: by, title: quote.title, currency: quote.currency)
    invoice.copy_pricing_from(quote, lines: [])
    claims = job.claims.index_by(&:quote_line_item_id)
    billed = billed_job_line_ids(claims.values.filter_map(&:job_line_item_id))
    lines = quote.line_items.to_a
    invoice.sync_line_items(BuiltDocument.rows_from(lines)).zip(lines) do |item, line|
      job_line_id = claims[line.id]&.job_line_item_id
      item.assign_attributes(job_line_item_id: job_line_id, quote_line_item_id: line.id, final: job_line_id.present? && !billed.include?(job_line_id))
    end
    invoice.save!
    invoice
  end

  # PAY-08: "Create another invoice" before the work is done: a progress invoice of what's left of
  # each line of an open job, or of a quote's lines not yet done, which staff can lower. Its lines
  # aren't final bills; each is credited when its line is billed for real. The quote's discount
  # comes off as staff choose (`discount`). Not for recurring quotes (JOB-10).
  def bill_progress!(source, by: nil, discount: nil)
    Invoice.transaction do
      job = source if source.is_a?(Job)
      quote = job ? job.quote : source
      if quote
        Quote.where(id: quote.id).lock.pluck(:id)
        lock!(quote_id: quote.id, jobs: job ? [ job ] : quote.jobs.where.not(status: "cancelled").order(:id).to_a)
      else
        lock!(jobs: [ job ])
      end
      source.reload
      raise Refused, "#{quote.number} is recurring: each occurrence is billed from its own job." if quote&.recurring?

      ledger = BillingLedger.new(quote:, job: (job unless quote))
      raise Refused, BillingLedger::PROGRESS_BLOCKED if ledger.progress_blocked?

      lines = if job
        raise Refused, "#{job.number} is #{job.status}. Progress billing is for work not done yet." unless job.open?

        job.line_items.to_a
      else
        raise Invoice::NotApproved, "Only an approved quote can be invoiced." unless quote.approved?

        # A line a live job holds at other rates is billed as progress from that job's page.
        quote.line_items.reject { |line| ledger.done?(line) || ledger.live_jobs_of(line).any? { _1.tax_rate_list.to_set != quote.tax_rate_list.to_set } }
      end
      rows = lines.map { [ _1, ledger.left_cents(_1) ] }.select { _2.positive? }
      raise Refused, "Nothing on #{source.number} is left to bill as progress." if rows.empty?

      invoice = Invoice.new(kind: "progress", client: source.client, property: source.property, job:, quote:, created_by: by, title: source.title, currency: source.currency)
      invoice.copy_pricing_from(source, lines: [])
      quote_discount_off!(invoice)
      items = invoice.sync_line_items(BuiltDocument.rows_from(rows.map(&:first)))
      items.zip(rows) do |item, (line, _)|
        item.assign_attributes(job_line_item_id: (line.id if job), quote_line_item_id: (job ? line.claim&.quote_line_item_id : line.id), final: false)
        item.set_discount(nil, nil) if item.discount_kind == "amount"
      end
      fit_progress!(invoice, items.zip(rows.map(&:last)))
      invoice.quote_discount_applied = discount
      leave_room_for_the_discount!(invoice, ledger, items) if quote && invoice.quote_discount_chosen_cents.to_i.zero?
      invoice.save!
      invoice.record!(:created, by:, from: job ? "job" : "quote", number: source.number)
      invoice
    end
  end

  # Each progress line charges, net of the invoice's discounts, at most what's left of its line (the
  # final's net for the rest): one over becomes 1 × the price that charges what's left, found from
  # what the discounts leave of it, then lowered a cent at a time for rounding.
  def fit_progress!(invoice, items_with_left)
    8.times do
      over = items_with_left.zip(invoice.totals(credits: false).lines).select { |(_, left), result| result.taxable.cents > left }
      break if over.empty?

      over.each do |(item, left), result|
        gross = result.subtotal.cents
        price = result.taxable.cents.positive? ? (left * gross / result.taxable.cents.to_d).floor : left
        price = [ price, item.unit_price_cents.to_i - 1 ].min if item.quantity.to_d == 1
        item.set_discount(nil, nil) if item.discount_kind == "amount"
        item.assign_attributes(quantity: 1, unit: nil, unit_price_cents: [ price, 0 ].max)
      end
    end
  end

  # With "Apply later", progress leaves room for the quote's discount still to come: the work left,
  # less progress not yet credited, must take it (owner, 2026-11-23). Lines are lowered in
  # proportion when they'd charge more; with no room at all, the minimum applies instead.
  # Per group (taxed, untaxed: B20): each group's lines leave room for that group's part.
  def leave_room_for_the_discount!(invoice, ledger, items)
    charges = invoice.totals(credits: false).lines.map { [ _1.taxable.cents, 0 ].max }
    work, owed, outstanding = ledger.work_left_by_group, ledger.uncredited_by_group, ledger.outstanding_by_group
    lefts = charges.dup
    items.each_index.group_by { ledger.group_of(items[_1]) }.each do |group, indexes|
      room = work[group] - owed[group] - outstanding.fetch(group, 0)
      asked = indexes.sum { charges[_1] }
      next unless room.positive? && asked > room

      Money.new(room, invoice.currency).allocate(indexes.map { charges[_1] }).zip(indexes) { |part, i| lefts[i] = part.cents }
    end
    fit_progress!(invoice, items.zip(lefts)) if lefts != charges
  end

  # A quote's discount, fixed or percent, comes off its invoices as staff choose (PAY-08, owner
  # 2026-11-23), so invoices for its work don't copy it.
  def quote_discount_off!(invoice)
    invoice.set_discount(nil, nil) if invoice.quote_id
  end

  # Job lines (or [line, own tax rates]) as invoice lines that bill them: the final bill unless
  # one exists (before split jobs a job can be billed again; those are progress).
  def add_job_lines(invoice, lines)
    lines = lines.map { Array(_1) }
    billed = billed_job_line_ids(lines.map { _1.first.id })
    items = invoice.sync_line_items(BuiltDocument.rows_from(lines.map(&:first)))
    items.zip(lines) do |item, (line, rates)|
      item.assign_attributes(job_line_item_id: line.id, quote_line_item_id: line.claim&.quote_line_item_id, final: !billed.include?(line.id), tax_rates: rates)
    end
  end

  def check_priced!(lines)
    unpriced = lines.select(&:price_pending)
    raise Invoice::Unpriced, "Price #{unpriced.map(&:name).to_sentence} first: added on site without a price." if unpriced.any?
  end

  # "INV-0003 and INV-0004": the invoices holding these lines' final bills.
  def billed_on(job_lines)
    Invoice.where(id: InvoiceLineItem.final_bills.where(job_line_item_id: job_lines.map(&:id)).select(:invoice_id)).order(:id).pluck(:number).to_sentence
  end
end
