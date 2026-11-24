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
  APPLY_ALL = 1_000_000_000_000 # "Apply all": as much of the quote's discount as the range allows

  included do
    has_many :credits, -> { order(:position, :id).includes(:source_invoice) }, class_name: "InvoiceCredit", inverse_of: :invoice,
                                                                                dependent: :delete_all, autosave: true

    validates :kind, inclusion: { in: KINDS }
    validate { errors.add(:base, "Quote discount: “#{@bad_discount.first(20)}” isn't an amount.") if @bad_discount }
    validate :progress_within_what_is_left, if: -> { progress? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    validate :keeps_credited_progress, if: -> { progress? && billing_credits? && sent_version }
    validate :progress_matches_on_tax_inclusion, if: -> { status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    validate :keeps_its_credits, if: -> { kind == "work" && sent_at_in_database && draft? && credits.any? && errors.empty? }
    before_save :work_out_credits, prepend: true, if: -> { kind == "work" && sent_at_in_database.nil? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    before_save :choose_progress_discount, prepend: true, if: -> { progress? && sent_at_in_database.nil? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    # Chosen before the checks, so a line's net is checked with the discount it takes now.
    before_validation :choose_progress_discount, if: -> { progress? && sent_at_in_database.nil? && status_in_database.in?([ nil, "draft" ]) && billing_credits? }
    validate :progress_leaves_room_for_the_discount, if: -> { progress? && status_in_database.in?([ nil, "draft" ]) && sent_at_in_database.nil? && billing_credits? }
    before_save { @progress_changed = progress? && sent_at_in_database && line_items.any?(&:changed_for_autosave?) }
    after_save(if: -> { @progress_changed }) { rework_drafts! }
  end

  def progress? = kind == "progress"

  # What it's called wherever it's named: "Progress invoice INV-0004", as on the client's page.
  def kind_label = progress? ? "Progress invoice" : "Invoice"

  # Prices the lines with the shares, and the pre-tax credits as negative lines (credits: false is
  # the total before credits, which the $0 rule looks at).
  def totals(credits: true)
    Pricing::DocumentTotals.new(currency:, discount: pricing_discount, prices_include_tax:, share: share_parts,
                                lines: current_line_items.map { _1.to_pricing(tax_rate_list) } + (credits ? pre_tax_credits.map(&:to_pricing) : []))
  end

  # The applied quote discount by tax mix: [[rates, Money]] (owner, 2026-11-23).
  def share_parts
    Array(quote_discount_parts).map { |part| [ part["rates"].map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }, Money.new(part["cents"].to_i, currency) ] }
  end

  def pre_tax_credits = credits.reject(&:marked_for_destruction?).select(&:pre_tax?)

  def quote_discount_share = Money.new(quote_discount_share_cents.to_i, currency)

  # The builder's "Apply now" (dollars, or "all"): staff's choice of how much of the quote's
  # discount this invoice applies (owner, 2026-11-23). It's held to the range on each save.
  def quote_discount_applied=(value)
    value = value.to_s.strip
    @bad_discount = nil
    self.quote_discount_chosen_cents = if value == "all" then APPLY_ALL
    elsif value.empty? then nil
    else Money.parse(value, currency).cents.clamp(0, APPLY_ALL)
    end
  rescue ArgumentError, TypeError, FloatDomainError
    @bad_discount = value
  end

  # For the builder: { left:, min:, max:, work_left: } in cents, or nil when there's nothing to
  # choose (no discount left, not quote work, sent already).
  def quote_discount_range
    return unless billing_credits? && quote && sent_at.nil? && draft?

    lock_billing!
    range = discount_range(BillingLedger.for(self))
    range if range[:left].positive?
  end

  # What the client sees (owner, 2026-11-23): one "Credit from INV-0004" per invoice credited, as
  # it charged: each source's credits with their own tax at their own rates. Only the rounding
  # left over (the invoice rounds tax once per rate) is split, so together they make the difference.
  def client_credits
    groups = pre_tax_credits.group_by(&:source_invoice)
    return [] if groups.empty?

    charged = groups.values.map do |list|
      tax = prices_include_tax ? 0 : list.flat_map { |credit| credit.tax_rate_list.map { [ _1, credit.amount_cents ] } }
                                         .group_by(&:first).sum { |rate, pairs| (pairs.sum(&:last) * rate.percent / 100).round(0, Money::ROUNDING).to_i }
      list.sum(&:amount_cents) + tax
    end
    rest = Money.new((totals(credits: false).total - totals.total).cents - charged.sum, currency).allocate(charged.map { [ _1, 1 ].max })
    groups.keys.zip(charged.zip(rest).map { Money.new(_1, currency) + _2 })
  end

  # { line key => net charged } for this invoice: what each line charged, net of its discounts and
  # before tax. While a sent invoice is being revised, what the version the client has charged.
  def charged_by_key = (version = sent_version) ? charges_from(version.snapshot) : current_charges

  # B1: a discard puts back the version the client has; refused if that charges a credited line
  # less than was credited (credits follow the sent version, so this only guards).
  def check_discard_against_credits!(previous)
    return unless progress? && billing_credits?

    used = InvoiceCredit.counted.where(source_line_item_id: line_items.map(&:id)).where.not(invoice_id: id).group(:source_line_item_id).sum(:amount_cents)
    restored = charges_from(previous.snapshot)
    short = line_items.select { used[_1.id].to_i > restored[_1.key].to_i }
    raise ArgumentError, "#{short.map(&:name).to_sentence} is credited on #{crediting_invoices.pluck(:number).to_sentence} for more than that version charged. Void that invoice first." if short.any?
  end

  # The version the client was sent, while a sent invoice is being revised.
  def sent_version = (revisions.last if revision.to_i > 1 && status_in_database == "draft")

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

  def current_charges = current_line_items.map(&:key).zip(net_by_line.values_at(*current_line_items)).to_h

  # What each line charges, net of this invoice's discounts, the applied quote discount included:
  # each part comes off the lines taxed at its rates, in proportion: the same base its tax is
  # worked out on, so a progress invoice's credit is exactly what it charged. (A part whose lines
  # can't take it all, from an older plan, comes off the rest.)
  def net_by_line(priced = totals(credits: false))
    lines = current_line_items
    net = lines.zip(priced.lines).to_h { |line, result| [ line, result.taxable.cents ] }
    take = lambda do |group, cents| # off these lines in proportion, never below zero; returns what's left
      weights = group.map { [ net[_1], 0 ].max }
      cents = [ cents, weights.sum ].min.tap { |taken| Money.new(taken, currency).allocate(weights).zip(group) { |part, line| net[line] -= part.cents } if taken.positive? }
      cents
    end
    share_parts.each do |rates, amount|
      group = lines.select { BillingLedger.group(rates_for(_1)) == BillingLedger.group(rates) }
      rest = amount.cents - (group.any? ? take.(group, amount.cents) : 0)
      take.(lines, rest) if rest.positive? # an untaxed part with too few untaxed lines comes off the rest
    end
    net
  end

  def apply_quote_discount!(range)
    self.quote_discount_share_cents = range[:applied]
    self.quote_discount_parts = range[:plan] ? range[:plan].parts(range[:applied]).map { { "from" => rates_json(_1.from), "rates" => rates_json(_1.rates), "cents" => _1.cents } } : []
  end

  def rates_json(rates) = rates.map { { "name" => _1.name, "percent" => _1.percent.to_d.to_s("F") } }

  # A revision snapshot priced again, in memory.
  def charges_from(data)
    copy = Invoice.new(business:, currency:, tax_rates: data["tax_rates"], prices_include_tax: data["prices_include_tax"],
                       quote_discount_share_cents: data["quote_discount_share_cents"].to_i, quote_discount_parts: data["quote_discount_parts"].to_a)
    copy.set_discount(data["discount_kind"], data["discount"])
    data["lines"].each_with_index do |line, position|
      item = copy.line_items.build(line.slice(*%w[key name quantity unit_price_cents taxable tax_rates discount_share_cents]).merge("position" => position))
      item.set_discount(line["discount_kind"], line["discount"])
    end
    copy.send(:current_charges)
  end

  def lock_billing!
    quote_id ? QuoteWork.lock!(quote_id) : WorkBilling.lock!(jobs: [ job_id ])
  end

  def work_out_credits
    lock_billing!
    ledger = BillingLedger.for(self)
    lines = current_line_items
    finals = lines.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }
    share_lines(ledger, lines, finals)
    apply_quote_discount!(discount_range(ledger, finals:))
    wanted = credits_wanted(ledger, finals)
    return if wanted == pre_tax_credits.map { _1.snapshot.symbolize_keys }

    credits.each(&:mark_for_destruction)
    wanted.each { credits.build(**_1, business:) }
  end

  # Each final bill takes, at most, what this invoice charges for its line: net of the applied
  # discount and this invoice's own, before tax (the same measure as the progress it credits).
  def credits_wanted(ledger, finals)
    lines = current_line_items
    priced = totals(credits: false)
    net = net_by_line(priced).transform_values { [ _1, 0 ].max }
    caps = finals.map { |line| [ line, net[line], rates_for(line) ] }
    others = lines.reject { _1.job_line_item_id || _1.quote_line_item_id }.sum { net[_1] }
    ledger.credits_for(caps, others_cap: others, bases: tax_bases(priced))
  end

  # The quote's discount this invoice may apply (owner, 2026-11-23), in cents:
  # - left: what's still to apply, less other work invoices that aren't void (progress only moves
  #   cash: its final credits the net it charged);
  # - max: left, and no more than this invoice charges (by choice, less its credits: progress is
  #   capped by what the final charges);
  # - min: what the work left after it can't absorb, overall (left − (work still to bill −
  #   progress not yet credited, after this bill's credits; on progress, its own charge too)) and
  #   for each tax group (its `needs`, so the tax matches the quote's where the work allows);
  # - applied: staff's choice (nil: $0, "Apply later") held to [min, max]; short: min > max, the
  #   work left charging less than the discount left;
  # - plan: how the applied amount is split by tax (QuoteDiscountPlan).
  def discount_range(ledger, finals: nil)
    left = ledger.outstanding_cents
    return { left: 0, min: 0, max: 0, applied: 0, work_left: 0, short: false, charge: 0 } unless left.positive?

    saved = [ quote_discount_share_cents, quote_discount_parts ]
    self.quote_discount_share_cents = 0
    self.quote_discount_parts = []
    priced = totals(credits: false)
    lines = current_line_items
    charge_by = lines.zip(priced.lines).each_with_object(Hash.new(0)) { |(line, result), sums| sums[BillingLedger.group(rates_for(line))] += [ result.taxable.cents, 0 ].max }
    charge = charge_by.values.sum
    work = ledger.work_left_by_group(billed: progress? ? [] : (finals ||= lines.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }))
    owed = ledger.uncredited_by_group
    credited = Hash.new(0)
    if progress?
      charge_by.each { |rates, cents| owed[rates] += cents } # its own charge waits to be credited too
    else
      credits_wanted(ledger, finals).each do |credit|
        group = BillingLedger.group(BillingLedger.rates_from(credit[:tax_rates]))
        owed[group] -= credit[:amount_cents]
        credited[group] += credit[:amount_cents]
      end
    end
    self.quote_discount_share_cents, self.quote_discount_parts = saved
    room = work.values.sum - owed.values.sum
    outstanding = ledger.outstanding_by_group
    # Each tax group takes now what its own work left can't, as far as this invoice's lines at its
    # rates allow (beyond that, a later invoice's other lines take it: the money still adds up).
    needs = outstanding.to_h { |rates, cents| [ rates, (cents - (work[rates] - owed[rates])).clamp(0, [ cents, charge_by[rates] ].min) ] }
    plan = QuoteDiscountPlan.new(outstanding:, capacity: charge_by, free: charge_by.to_h { |rates, cents| [ rates, cents - credited[rates] ] }, needs:)
    must = [ left - room, 0 ].max # what no later invoice can take
    min = [ must, needs.values.sum ].max
    # What isn't needed now isn't routed onto other rates: it waits for lines at its own.
    most = [ left, charge ].min.clamp(0..)
    # By choice, no more than leaves this invoice's credits whole (what must go now still goes).
    max = [ most, [ plan.fits, min ].max ].min
    applied = (quote_discount_chosen_cents || 0).clamp(0, max)
    applied = [ applied, min ].max.clamp(0, max)
    { left:, min: [ min, max ].min, max:, applied:, work_left: [ room, 0 ].max, short: must > most, charge:,
      plan: }
  end

  def choose_progress_discount
    lock_billing!
    apply_quote_discount!(discount_range(BillingLedger.for(self)))
  end

  # A progress invoice can't charge so much that the work left can't take the rest of the
  # quote's discount, even with all of it applied now.
  def progress_leaves_room_for_the_discount
    return unless quote_id

    lock_billing!
    range = discount_range(BillingLedger.for(self))
    return unless range[:short]

    errors.add(:base, "This leaves too little work to take the rest of the quote's discount " \
                      "(#{Money.new(range[:left], currency).format}). Lower it, or apply the discount on it.")
  end

  # What each tax rate is charged on before credits, after the applied quote discount.
  def tax_bases(priced = totals(credits: false))
    bases = priced.lines.each_with_object(Hash.new(0)) { |line, sums| line.line.tax_rates.each { sums[_1] += line.taxable.cents } }
    share_parts.each { |rates, amount| rates.each { bases[_1] -= amount.cents } }
    bases
  end

  def rates_for(line) = line.taxable ? (line.own_tax_rate_list || tax_rate_list) : []

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

  # "Roof: only $500.00 is left to bill." What each line charges, net of this invoice's discounts,
  # against what the final would charge for the rest of it (owner, 2026-11-23). Until it's first
  # sent, every line (so a draft sent after the final bill is refused); on a revision, only what
  # charges more than the version the client has.
  def progress_within_what_is_left
    lock_billing!
    ledger = BillingLedger.for(self)
    now = current_charges
    sent = (version = sent_version) ? charges_from(version.snapshot) : nil
    current_line_items.reject(&:final).select { _1.job_line_item_id || _1.quote_line_item_id }
                      .group_by { _1.job_line_item_id ? [ :job, _1.job_line_item_id ] : [ :quote, _1.quote_line_item_id ] }.each do |(kind, id), group|
      asked = group.sum { now[_1.key] }
      next if sent && asked <= group.sum { sent[_1.key].to_i }

      work = kind == :job ? ledger.job_line(id) : ledger.quote_line(id)
      left = work ? ledger.left_cents(work) : 0
      next if asked <= left

      finals = work && left.zero? ? ledger.final_invoices(work) : []
      if finals.any?
        errors.add(:base, "#{group.first.name.presence || "Item"} is on #{finals.map(&:number).to_sentence}, its final bill#{" (a draft)" if finals.all?(&:draft?)}, " \
                          "so nothing is left to bill as progress.")
      else
        errors.add(:base, "#{group.first.name.presence || "Item"}: only #{Money.new(left, currency).format} is left to bill.")
      end
    end
  end

  # Progress credited on a later invoice stays as it was charged: a revision can't change what a
  # credited line charges (its amount, any discount spread onto it) or how it's taxed, against the
  # version the client has. Void that invoice first.
  def keeps_credited_progress
    used = InvoiceCredit.counted.where(source_line_item_id: line_items.filter_map(&:id)).where.not(invoice_id: id).group(:source_line_item_id).sum(:amount_cents)
    return if used.empty?

    data = sent_version.snapshot
    sent = charges_from(data)
    now = current_charges
    was = data["lines"].index_by { _1["key"] }
    short = line_items.select do |line|
      next false unless used[line.id]

      old = was[line.key]
      line.marked_for_destruction? || old.nil? || now[line.key] != sent[line.key] || line.taxable != old["taxable"] || line.tax_rates != old["tax_rates"]
    end
    whole = data["tax_rates"] != tax_rates || data["prices_include_tax"] != prices_include_tax
    short = line_items.select { used[_1.id] } if short.empty? && whole
    return if short.empty?

    errors.add(:base, "#{short.map { _1.name.presence || "Item" }.to_sentence} #{short.one? ? "is" : "are"} credited on " \
                      "#{crediting_invoices.pluck(:number).to_sentence}, so its amount, discount and tax stay as charged. Void that invoice first.")
  end

  # A sent work invoice's revision keeps its shares and credits: it can't go below them, overall or
  # for any line (a line's own progress, then its quote line's, never more than the line charges).
  def keeps_its_credits
    before = totals(credits: false)
    after = totals
    whole = (after.subtotal - after.discount + after.credit_total).negative? || after.discount < before.discount || after.taxes.any? { _1.amount.negative? }
    return unless whole || lines_below_credits?(before)

    errors.add(:base, "That takes #{number} below what it credits for #{pre_tax_credits.map { _1.source_invoice.number }.uniq.to_sentence}. Void it and bill again instead.")
  end

  def lines_below_credits?(priced)
    ledger = BillingLedger.for(self)
    by_source = pre_tax_credits.select { _1.kind == "progress" }.group_by(&:source_line_item_id).transform_values { _1.sum(&:amount_cents) }
    net = net_by_line(priced)
    finals = current_line_items.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }
    own = finals.any? { |line| ledger.pool(ledger.home(line)).sum { by_source[_1.id].to_i } > net[line] }
    shared = finals.select(&:quote_line_item_id).group_by(&:quote_line_item_id).any? do |id, group|
      (group.flat_map { ledger.pools_of(_1) } + ledger.pool([ :quote, id ])).uniq.sum { by_source[_1.id].to_i } > group.sum { net[_1] }
    end
    own || shared
  end

  # Progress and the bills that credit it agree on whether prices include tax (else tax would be
  # credited at a different base): a progress invoice matches its work, a work invoice its progress.
  def progress_matches_on_tax_inclusion
    source = progress? ? (job || quote) : nil
    ledger = BillingLedger.for(self) unless source
    progress_matches_its_work_on_tax_rates(source) if source
    mismatched = if source then source.prices_include_tax != prices_include_tax
    else
      ledger.progress.select { _1.invoice.sent_at && _1.invoice.prices_include_tax != prices_include_tax }.map { _1.invoice.number }.uniq.presence
    end
    if mismatched
      errors.add(:prices_include_tax, source ? "must match #{source.number} (#{source.prices_include_tax ? "prices include tax" : "tax is added"})" \
                                             : "must match #{mismatched.to_sentence}, whose progress it credits")
    end
    # A work invoice is made even when its progress was taxed otherwise (it credits none of that),
    # so staff can match the tax on the draft; saving it again or sending it is refused till then.
    progress_matches_on_tax_rates(ledger) if ledger && kind == "work" && persisted?
  end

  # A progress invoice is taxed as its job or quote is, line by line, so its final can credit it.
  def progress_matches_its_work_on_tax_rates(source)
    return errors.add(:tax_rates, "must match #{source.number}'s, so the final invoice can credit it") if tax_rate_list.to_set != source.tax_rate_list.to_set

    ledger = BillingLedger.for(self)
    current_line_items.select { _1.job_line_item_id || _1.quote_line_item_id }.each do |line|
      work = line.job_line_item_id ? ledger.job_line(line.job_line_item_id) : ledger.quote_line(line.quote_line_item_id)
      next if work.nil?

      unless line.taxable == work.taxable && line.tax_rates.nil?
        next errors.add(:base, "#{line.name.presence || "Item"} is taxed as on #{source.number}, so the final invoice can credit it.")
      end
      # Progress on a quote line a live job holds is taxed as that job will bill it.
      other = work.is_a?(QuoteLineItem) ? ledger.live_jobs_of(work).reject { _1.tax_rate_list.to_set == tax_rate_list.to_set && _1.prices_include_tax == prices_include_tax } : []
      next if other.empty?

      errors.add(:base, "#{line.name.presence || "Item"} is on #{other.map(&:number).to_sentence}, taxed at #{taxed(other.first.tax_rate_list)}: " \
                        "bill its progress from #{other.one? ? "that job's" : "each job's"} page.")
    end
  end

  def taxed(list) = list.any? ? list.map { "#{_1.name} #{_1.percent.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")}%" }.to_sentence : "no tax"

  # A final bill credits its line's progress at the rates it was charged at: a line taxed
  # otherwise is refused, so the credit always equals what was charged.
  def progress_matches_on_tax_rates(ledger)
    current_line_items.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }.each do |line|
      rates = rates_for(line).to_set
      other = ledger.pools_of(line).select { ledger.remaining_cents(_1).positive? && ledger.rates_of(_1).to_set != rates }
      next if other.empty?

      sources = other.map(&:invoice).uniq
      undo = sources.all?(&:voidable?) ? "void #{sources.one? ? "it" : "them"} first" : "refund #{sources.one? ? "its" : "their"} payments and void #{sources.one? ? "it" : "them"} first"
      errors.add(:base, "#{line.name.presence || "Item"} is taxed at #{taxed(rates.to_a)}, but #{sources.map(&:number).to_sentence} " \
                        "charged #{taxed(ledger.rates_of(other.first))} for it. Set this invoice's tax to #{taxed(ledger.rates_of(other.first))} to credit it, or #{undo}.")
    end
  end
end
