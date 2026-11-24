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
    validate { errors.add(:base, "Quote discount: “#{@bad_discount.first(20)}” isn't an amount. Type dollars and cents, like 1,250.00.") if @bad_discount }
    validate :takes_the_rest_of_the_quote_discount, if: -> { kind == "work" && quote_id && status_in_database == "draft" && sent_at_in_database.nil? && status == "sent" && billing_credits? }
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

  # The applied quote discount by the rates of the lines it comes off: [[rates, Money]] (owner,
  # 2026-11-23).
  def share_parts
    Array(quote_discount_parts).reject { _1["owed"] }.group_by { BillingLedger.group(BillingLedger.rates_from(_1["rates"])) }
                               .map { |rates, parts| [ rates, Money.new(parts.sum { _1["cents"].to_i }, currency) ] }
  end

  def pre_tax_credits = credits.reject(&:marked_for_destruction?).select(&:pre_tax?)

  def quote_discount_share = Money.new(quote_discount_share_cents.to_i, currency)

  # What this invoice charges back of the quote's discount: a shortfall after more was applied
  # (owner, 2026-11-24).
  def quote_discount_charge_back = Money.new(-Array(quote_discount_parts).sum { _1["cents"].to_i.negative? && !_1["owed"] ? _1["cents"].to_i : 0 }, currency)

  # The builder's "Apply now" (dollars, or "all"): staff's choice of how much of the quote's
  # discount this invoice applies (owner, 2026-11-23). It's held to the range on each save.
  # Plain dollars only: 1250, 1,250.5 or $1,250.00. "40,00", "4,0000" and "1e3" are refused, not
  # guessed at.
  AMOUNT = /\A\$?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?\z/

  def quote_discount_applied=(value)
    value = value.to_s.strip
    @bad_discount = nil
    self.quote_discount_chosen_cents = if value == "all" then APPLY_ALL
    elsif value.empty? then nil
    elsif value.match?(AMOUNT) then (value.delete("$,").to_d * 100).round.clamp(0, APPLY_ALL)
    else
      @bad_discount = value
      quote_discount_chosen_cents
    end
  end

  # When the amount typed was held to the range: :min or :max (for the hint).
  def quote_discount_held(range)
    chosen = quote_discount_chosen_cents
    return if chosen.nil? || chosen.zero? || chosen == APPLY_ALL || chosen == range[:applied] # $0 under a minimum: the hint says why

    chosen < range[:applied] ? :min : :max
  end

  # For the builder: { left:, min:, max:, work_left: } in cents, or nil when there's nothing to
  # choose (no discount left, not quote work, sent already).
  def quote_discount_range
    return unless billing_credits? && quote && sent_at.nil? && draft?

    lock_billing!
    range = discount_range(BillingLedger.for(self))
    range if range[:left].positive? || range[:charge_back].to_i.positive?
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
  # each part comes off the line it was placed on, at that line's rates: the same base its tax is
  # worked out on, so a progress invoice's credit is exactly what it charged.
  def net_by_line(priced = totals(credits: false))
    lines = current_line_items
    net = lines.zip(priced.lines).to_h { |line, result| [ line, result.taxable.cents ] }
    by_key = lines.index_by(&:key)
    Array(quote_discount_parts).each { |part| (line = by_key[part["key"]]) && net[line] -= part["cents"].to_i }
    net
  end

  def apply_quote_discount!(range)
    self.quote_discount_share_cents = range[:applied]
    parts = range[:plan] ? range[:plan].parts(range[:applied]) : []
    taken = parts.group_by(&:from).transform_values { _1.sum(&:cents) }
    owed = range[:owed].to_i.positive? ? range[:plan].outstanding.map { |group, cents| [ group, cents - taken.fetch(group, 0) ] }.select { _2.positive? } : []
    self.quote_discount_parts = parts.map { { "from" => rates_json(_1.from), "key" => _1.key, "rates" => rates_json(_1.rates), "cents" => _1.cents } } +
                                range[:back].to_a + owed.map { |group, cents| { "from" => rates_json(group), "rates" => rates_json(group), "owed" => true, "cents" => cents } }
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
  def credits_wanted(ledger, finals, taken: Hash.new(0))
    lines = current_line_items
    priced = totals(credits: false)
    net = net_by_line(priced).transform_values { [ _1, 0 ].max }
    caps = finals.map { |line| [ line, net[line], rates_for(line) ] }
    others = lines.reject { _1.job_line_item_id || _1.quote_line_item_id }.sum { net[_1] }
    # B13: a charge-back (a shortfall's discount added back) is charged too, on no line: over-billing
    # comes off it as well. Its rates' bases already include it (tax_bases), so its tax goes too.
    others += quote_discount_charge_back.cents
    ledger.credits_for(caps, others_cap: others, bases: tax_bases(priced), taken:)
  end

  # The quote's discount this invoice may apply (owner, 2026-11-23), in cents:
  # - left: what's still to apply, less other work invoices that aren't void (progress only moves
  #   cash: its final credits the net it charged);
  # - max: left, no more than this invoice charges, and by choice no more than its lines take
  #   keeping its credits whole (progress is capped by what the final charges);
  # - min: what the work left after it can't absorb, overall (left − (work still to bill −
  #   progress not yet credited, after this bill's credits; on progress, its own charge too)) and
  #   for each group, taxed or not (its `needs`, so the tax matches the quote's where it can);
  # - applied: staff's choice (nil: $0, "Apply later") held to [min, max]; short: min > max, the
  #   invoice charging less than the work left can't take (sending it is refused);
  # - plan: which lines it comes off (QuoteDiscountPlan).
  # This bill's credits are what they are with none of it applied: the plan keeps them whole.
  def discount_range(ledger, finals: nil)
    left = ledger.outstanding_cents
    over_applied = ledger.net_outstanding_by_group.select { _2.negative? }
    unless left.positive? || over_applied.any?
      return { left: 0, min: 0, max: 0, applied: 0, work_left: 0, short: false, charge: 0, unused: ledger.unused_discount_cents }
    end

    saved = [ quote_discount_share_cents, quote_discount_parts ]
    self.quote_discount_share_cents = 0
    self.quote_discount_parts = []
    priced = totals(credits: false)
    lines = current_line_items
    net = lines.zip(priced.lines).to_h { |line, result| [ line, [ result.taxable.cents, 0 ].max ] }
    work = ledger.work_left_by_group(billed: progress? ? [] : (finals ||= lines.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }))
    owed = ledger.uncredited_by_group
    taken = Hash.new(0)
    if progress?
      lines.each { owed[ledger.group_of(_1)] += net[_1] } # its own charge waits to be credited too
    else
      over = 0
      credits_wanted(ledger, finals, taken:).each do |credit|
        owed[ledger.progress_group(credit[:source_line_item_id])] -= credit[:amount_cents]
        over += credit[:amount_cents] if credit[:kind] == "over_billed"
      end
      free = lines.to_h { [ _1, net[_1] - taken[_1] ] }
      Money.new([ over, free.values.sum ].min, currency).allocate(free.values.map { [ _1, 0 ].max }).zip(free.keys) { |part, line| taken[line] += part.cents } if over.positive? && free.values.sum.positive?
    end
    self.quote_discount_share_cents, self.quote_discount_parts = saved
    slots = lines.map { QuoteDiscountPlan::Slot.new(key: _1.key, group: ledger.group_of(_1), rates: BillingLedger.group(rates_for(_1)), capacity: net[_1], free: net[_1] - taken[_1]) }
    room = work.values.sum - owed.values.sum
    # The last invoice once a shortfall is final (owner, 2026-11-24): it charges back what earlier
    # invoices applied past a group's scaled part, at the rates it came off, and takes the rest.
    last = !progress? && ledger.all_done? && work.values.sum.zero?
    outstanding = last ? ledger.net_outstanding_by_group.select { _2.positive? } : ledger.outstanding_by_group
    left = outstanding.values.sum if last
    back = last ? charge_back_parts(ledger, over_applied) : []
    plan = QuoteDiscountPlan.new(outstanding:, slots:)
    # Each group takes now what its own work left can't, as far as its lines here allow (beyond
    # that, a later invoice's other lines take it, or the minimum overall does).
    needs = outstanding.to_h { |group, cents| [ group, (cents - (work[group] - owed[group])).clamp(0, [ cents, plan.capacity(group) ].min) ] }
    plan = QuoteDiscountPlan.new(outstanding:, slots:, needs:)
    must = left - room.clamp(0..) # what no later invoice can take (progress billed past the work is over-billed, not this)
    min = [ must, needs.values.sum ].max
    most = [ left, net.values.sum ].min
    max = [ most, [ plan.fits, min ].max ].min
    applied = [ (quote_discount_chosen_cents || 0).clamp(0, max), min ].max.clamp(0, max)
    short = min > most
    # What the last invoice can't take of a scaled discount is owed to the client (owner,
    # 2026-11-24); an earlier one takes what fits and the rest carries to the last. Only a staff
    # discount leaving too little refuses a work invoice (R4); progress always leaves room.
    owed = short && last && discount_kind.blank? ? min - most : 0
    refuse = short && (progress? || discount_kind.present?)
    { left:, min: [ min, max ].min, max:, applied:, work_left: [ room, 0 ].max, short: refuse, charge: net.values.sum,
      unused: ledger.unused_discount_cents, plan:, back:, owed:, charge_back: -back.sum { _1["cents"] } }
  end

  # The parts charged back: each over-applied group's excess, at the rates its parts came off.
  def charge_back_parts(ledger, over_applied)
    applied = ledger.applied_by_group
    over_applied.flat_map do |group, cents|
      by_rates = applied[group].select { _2.positive? }
      next [] if by_rates.empty?

      Money.new(-cents, currency).allocate(by_rates.values).zip(by_rates.keys).filter_map do |part, rates|
        { "from" => rates_json(group), "rates" => rates_json(rates), "cents" => -part.cents } if part.positive?
      end
    end
  end

  # R4 (owner, 2026-11-23): a work invoice that can't take what the work left can't is refused,
  # as progress is, until staff lower its own discount.
  def takes_the_rest_of_the_quote_discount
    lock_billing!
    range = discount_range(BillingLedger.for(self))
    return unless range[:short]

    errors.add(:base, "This invoice charges too little to take the rest of the quote's discount " \
                      "(#{Money.new(range[:left], currency).format} left, #{Money.new(range[:max], currency).format} fits). " \
                      "#{discount_kind.present? ? "Lower its own discount" : "Add to what it bills"} to send it.")
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

  # How to undo a progress invoice, in the order the app allows: what credits it first (void
  # first), then its own payments, then it.
  def undo_steps(progress)
    steps = progress.crediting_invoices.where.not(id:).map { _1.payments? ? "refund #{_1.number}'s payments and void it" : "void #{_1.number}" }
    (steps << (progress.payments? ? "refund #{progress.number}'s payments and void it" : "void #{progress.number}")).join(", then ")
  end

  def taxed(list) = list.any? ? list.map { "#{_1.name} #{_1.percent.to_d.round(4).to_s("F").sub(/\.?0+\z/, "")}%" }.to_sentence : "no tax"

  # A final bill credits its line's progress at the rates it was charged at: a line taxed
  # otherwise is refused, so the credit always equals what was charged.
  def progress_matches_on_tax_rates(ledger)
    current_line_items.select { _1.final && (_1.job_line_item_id || _1.quote_line_item_id) }.each do |line|
      rates = rates_for(line).to_set
      held = ledger.pools_of(line).select { ledger.remaining_cents(_1).positive? }
      other = held.select { ledger.rates_of(_1).to_set != rates }
      next if other.empty?

      charged = other.group_by { ledger.rates_of(_1).to_set }.map { |set, lines| "#{lines.map { _1.invoice.number }.uniq.to_sentence} charged #{taxed(set.to_a)}" }
      undo = other.map(&:invoice).uniq.map { undo_steps(_1) }.to_sentence
      # One rate set elsewhere and none here: matching this invoice's tax is a way out too. Progress
      # at more than one set (a job re-taxed between progress invoices) leaves only the void.
      match = other.map { ledger.rates_of(_1).to_set }.uniq.one? && held.size == other.size ? "Set this invoice's tax to #{taxed(ledger.rates_of(other.first))} to credit it, or #{undo} first." : "#{undo.upcase_first} first."
      errors.add(:base, "#{line.name.presence || "Item"} is taxed at #{taxed(rates.to_a)}, but #{charged.to_sentence} for it. #{match}")
    end
  end
end
