require "test_helper"

# PAY-08: progress billing, credits and discount shares, with split jobs on. The worked examples
# from #356 are rerun here, in exact cents. Every test ends reconciled (JOB-09).
class ProgressBillingTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    as_business(@business) { @business.update!(auto_create_jobs: false) }
  end

  teardown { assert_empty as_business(@business) { JobClaim.unreconciled_lines.pluck(:id) }, "claimed = the sum of live claims" }

  # Owner, 2026-11-23: "Credit from INV-x" equals what INV-x charged. Every progress invoice whose
  # lines are all credited, on invoices that went out, was credited exactly what it charged.
  teardown do
    as_business(@business) do
      Invoice.where(kind: "progress").where.not(sent_at: nil).where.not(status: "void").find_each do |progress|
        used = InvoiceCredit.counted.where(source_invoice_id: progress.id).sum(:amount_cents)
        next unless used.positive? && used == progress.totals.lines.sum { _1.taxable.cents }

        crediting = Invoice.where(id: InvoiceCredit.counted.where(source_invoice_id: progress.id).select(:invoice_id)).to_a
        shown = crediting.sum { |invoice| invoice.client_credits.sum { |source, amount| source == progress ? amount.cents : 0 } }
        # Each credit carries the tax its progress charged on it (B14): exactly, however it's split,
        # and no cent is kept or owed (owner, 2026-11-24).
        assert_equal progress.total_cents, shown, "Credit from #{progress.number} equals what it charged"
      end
    end
  end

  # An approved quote with these lines ([key, name, quantity, price]).
  def approved_quote(lines, tax: nil, discount: nil, line_discounts: {}, line_percents: {}, untaxed: [], percent: nil, inclusive: false, quick: false)
    @quote = as_business(@business) do
      client = (@client if quick) || Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.tax_rate_list = Array(tax).each_with_index.map { |percent, i| Pricing::TaxRate.new(name: i.zero? ? "State" : "County", percent:) }
      quote.set_discount("amount", discount) if discount
      quote.set_discount("percent", percent) if percent
      quote.prices_include_tax = inclusive
      quote.sync_line_items(lines.map do |key, name, quantity, price|
        { "key" => key, "name" => name, "quantity" => quantity.to_s, "unit_price" => price.to_s, "taxable" => (untaxed.include?(key) ? "0" : "1"),
          **(line_discounts[key] ? { "discount_kind" => "amount", "discount_value" => line_discounts[key].to_s } : {}),
          **(line_percents[key] ? { "discount_kind" => "percent", "discount_value" => line_percents[key].to_s } : {}) }
      end)
      quote.save!
      next quote.tap { _1.update_columns(status: "approved") } if quick # the randomized test: approval itself isn't under test

      quote.mark_sent!(by: @owner, channel: "link")
      quote.record_response!(:approve, by: @owner, signer_name: "Pat Lee", message: "By phone")
      quote.reload
    end
  end

  def line(key) = as_business(@business) { @quote.line_items.find_by!(key:).reload }
  def make(**quantities) = as_business(@business) { Job.from_quote!(@quote.reload, by: @owner, picks: quantities.to_h { [ line(_1.to_s).id, _2.to_s ] }) }
  def complete(job, done = {})
    as_business(@business) { job.reload.complete!(by: @owner, done: done.to_h { |name, quantity| [ job.line_items.find_by!(name:).id, quantity.to_s ] }) }
    job
  end
  def bill_job(job) = as_business(@business) { Invoice.from_job!(job.reload, by: @owner) }
  def bill_quote = as_business(@business) { Invoice.from_quote!(@quote.reload, by: @owner) }
  def progress(source) = as_business(@business) { WorkBilling.bill_progress!(source.reload, by: @owner) }
  def send!(invoice) = as_business(@business) { invoice.reload.mark_sent!(by: @owner, channel: "link") && invoice.reload }
  def total_tax(invoice) = as_business(@business) { invoice.reload.tax_cents }
  def total(invoice) = as_business(@business) { invoice.reload.total_cents }

  # Lowers a progress invoice's lines to these amounts ({ name => dollars }; nil takes it off).
  def lower(invoice, amounts)
    as_business(@business) do
      invoice.reload
      invoice.line_items.each do |item|
        next unless amounts.key?(item.name)

        amounts[item.name] ? item.assign_attributes(quantity: 1, unit_price: amounts[item.name].to_s) : item.mark_for_destruction
      end
      invoice.save!
      invoice.reload
    end
  end

  # "Credit from INV-x" as the client sees it, with its tax: what that invoice charged.
  def client_credits(invoice) = as_business(@business) { invoice.reload.client_credits.map { [ _1.number, _2.cents ] } }
  def credits(invoice) = as_business(@business) { invoice.reload.credits.map { [ _1.kind, _1.source_invoice.number, _1.amount_cents ] } }
  def cents(invoice) = as_business(@business) { invoice.reload }.then { [ _1.subtotal_cents, _1.discount_total_cents, _1.tax_cents, _1.total_cents ] }

  test "example 1: progress, then final with 10% tax: progress is credited before tax, so tax is charged once" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    assert_equal "progress", early.kind
    assert_equal [ 500_00, 0, 50_00, 550_00 ], cents(early)
    assert_not as_business(@business) { early.line_items.sole.final }

    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final)
    assert_equal [ 1000_00, 0, 50_00, 550_00 ], cents(final), "$1,000 less $500 billed earlier, then 10% tax"
    assert_equal "Billed earlier on #{early.number}", as_business(@business) { final.credits.sole.label }
    assert_equal 1100_00, early.total_cents + final.total_cents, "$1,000 + $100 tax in all"
  end

  test "example 2: a cancelled job's progress moves to its quote line and is credited on the job that does the work" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ])
    first = make(t: 6)
    early = send!(lower(progress(first), "Tree removal" => 300))
    as_business(@business) { first.reload.cancel!(by: @owner, reason: "Crew sick", notify_client: false) }

    second = complete(make(t: 6), "Tree removal" => 5)
    final = send!(bill_job(second))
    assert_equal [ [ "progress", early.number, 300_00 ] ], credits(final), "min($300, $500)"
    assert_equal [ 500_00, 0, 0, 200_00 ], cents(final)
    assert_equal 500_00, early.total_cents + final.total_cents, "$500 for $500 of work"
  end

  test "example 3: over-billing: progress past the work done is shown, then credited on the next invoice" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ], [ "g", "Gutters", 1, 300 ] ])
    early = send!(lower(progress(@quote), "Tree removal" => 800, "Gutters" => nil))
    trees = complete(make(t: 10), "Tree removal" => 6) # 4 not done (a shortfall: nothing left to do)
    final = bill_job(trees)
    assert_equal [ [ "progress", early.number, 600_00 ] ], credits(final), "min($800, $600)"
    assert_equal 0, final.total_cents
    assert as_business(@business) { final.sendable_total? }, "the $0 rule looks at the total before credits"
    assert_equal "paid", send!(final).status, "nothing due: Paid at once"
    assert_equal 200_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }

    gutters = send!(bill_job(complete(make(g: 1))))
    assert_equal [ [ "over_billed", early.number, 200_00 ] ], credits(gutters)
    assert_equal 100_00, gutters.total_cents
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
    assert_equal 900_00, early.total_cents + final.total_cents + gutters.total_cents, "$900 for $900 of work"
  end

  test "example 4, as the owner now has it: staff choose how much of the quote's discount comes off; the last invoice takes the rest" do
    approved_quote([ [ "a", "Mulch", 10, 50 ], [ "b", "Patio", 1, 500 ] ], discount: "100")
    first = send!(as_business(@business) { Invoice.from_job!(complete(make(a: 10)).reload, by: @owner).tap { _1.update!(quote_discount_applied: "30") } })
    assert_equal [ 30_00, 470_00 ], [ first.quote_discount_share_cents, first.total_cents ], "$30 now; $70 carries forward"
    assert_equal 70_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).outstanding_cents }
    second = send!(bill_job(complete(make(b: 1))))
    assert_equal [ 70_00, 430_00 ], [ second.quote_discount_share_cents, second.total_cents ], "the last invoice takes the rest"
  end


  test "progress leaves room for the discount still to come; charging more applies the minimum now" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = make(r: 1)
    early = progress(job)
    assert_equal [ 900_00, 0 ], [ early.reload.subtotal_cents, early.quote_discount_share_cents ], "Apply later: room for the $100"
    lower(early, "Roof" => 1000)
    assert_equal [ 100_00, 900_00 ], [ early.reload.quote_discount_share_cents, early.total_cents ], "at least the gap now"
    send!(early)
    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 900_00 ] ], credits(final), "what it charged"
    assert_equal [ 100_00, 0 ], [ final.quote_discount_share_cents, final.total_cents ], "the work's invoice gives the whole discount"
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
  end

  test "billing a quote directly takes its fixed discounts once: the line's share, and the quote's as the last invoice" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100", line_discounts: { "r" => 50 })
    invoice = bill_quote
    as_business(@business) do
      assert_nil invoice.reload.discount_kind
      assert_nil invoice.line_items.sole.discount_kind
      assert_equal [ 50_00, 100_00, 850_00 ], [ invoice.line_items.sole.discount_share_cents, invoice.quote_discount_share_cents, invoice.total_cents ]
    end
  end

  test "a progress draft sent after the line's final bill is refused" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    draft = lower(progress(job), "Roof" => 400)
    final = send!(bill_job(complete(job)))
    as_business(@business) do # B18: kept at $0 for staff to delete, within its cap, and its history says why
      assert_equal [ 0, [] ], [ draft.reload.total_cents, draft.tap(&:validate).errors.full_messages ]
      assert_equal "Nothing left to bill on Roof", ApplicationController.helpers.invoice_event_text(draft.events.find_by!(kind: "progress_refitted"))
    end
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(draft) }
    assert_match "Roof is on #{final.number}, its final bill, so nothing is left to bill as progress.", error.message
    assert_equal "draft", draft.reload.status
  end

  test "progress a draft credits can change on a revision: the draft works its credits out again; one that went out can't" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = bill_job(complete(job))
    assert_equal 550_00, final.reload.total_cents
    as_business(@business) { early.reload.revise!(by: @owner) }
    lower(early, "Roof" => nil)
    assert_empty credits(final), "its credit went with the line"
    assert_equal 1100_00, final.reload.total_cents

    as_business(@business) { early.reload.discard_revision!(by: @owner) }
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final), "the line is back, and the draft credits it again"
    send!(final)
    as_business(@business) { early.reload.revise!(by: @owner) }
    assert lower(early, {}), "saving it unchanged is fine"
    assert_match "credited on #{final.number}", assert_raises(ActiveRecord::RecordInvalid) { lower(early, "Roof" => 400) }.message
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.tax_rate_list = [] }.save! } }
    assert_match "its amount, discount and tax stay as charged", error.message
    assert_not as_business(@business) { early.reload.discard_revision!(by: @owner) && early.reload.voidable? }, "Void waits for #{final.number}"
  end

  test "a sent final invoice's revision keeps its shares and credits, and can't go below them" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    as_business(@business) { final.reload.revise!(by: @owner) }
    as_business(@business) { final.reload.tap { _1.set_discount("amount", "10") }.save! }
    assert_equal [ 100_00, [ [ "progress", early.number, 500_00 ] ], 390_00 ], [ final.reload.quote_discount_share_cents, credits(final), final.total_cents ]
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { final.reload.tap { _1.line_items.to_a.sole.unit_price = "300" }.save! } }
    assert_match "below what it credits for #{early.number}", error.message
  end

  test "a credit never takes a tax rate's base below zero: the rest stays over-billed" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ], [ "g", "Gutters", 1, 300 ] ], tax: "10", untaxed: [ "g" ])
    send!(lower(progress(@quote), "Tree removal" => 800, "Gutters" => nil))
    send!(bill_job(complete(make(t: 10), "Tree removal" => 6)))
    gutters = send!(bill_job(complete(make(g: 1))))
    assert_empty credits(gutters), "taxed over-billing can't come off untaxed work"
    assert_equal [ 300_00, 0, 300_00 ], [ gutters.subtotal_cents, gutters.tax_cents, gutters.total_cents ]
    assert_equal 200_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
  end

  test "progress and its bills agree on whether prices include tax" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    early = progress(make(r: 1))
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.prices_include_tax = true }.save! } }
    assert_match "Prices include tax must match J-", error.message
  end

  test "a quote line billed directly on a draft isn't finished: its progress isn't over-billed until the bill goes out" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ])
    early = send!(lower(progress(@quote), "Tree removal" => 800))
    draft = bill_quote
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
    assert_equal [ [ "progress", early.number, 800_00 ] ], credits(draft)
  end

  # Owner, 2026-11-23: a progress invoice's discounts apply to the cash collected on it; the final
  # deducts only the net amount it charged, so "Credit from" equals what it charged.
  test "B1: the quote's percent discount and tax: full progress, then the final comes to $0 and credits what was charged" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10", percent: "10")
    job = make(r: 1)
    early = send!(progress(job))
    assert_equal 990_00, early.total_cents
    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 900_00 ] ], credits(final), "net of the 10%, before tax"
    assert_equal [ 0, [ [ early.number, 990_00 ] ] ], [ final.total_cents, client_credits(final) ]
  end

  test "B1: the same with prices that include tax" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10", percent: "10", inclusive: true)
    job = make(r: 1)
    early = send!(progress(job))
    final = bill_job(complete(job))
    assert_equal [ 900_00, 0, [ [ early.number, 900_00 ] ] ], [ early.total_cents, final.total_cents, client_credits(final) ]
  end

  test "B1: a staff percent typed on the final caps its credit at what it charges; the rest is over-billed" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(progress(job))
    final = bill_job(complete(job))
    as_business(@business) { final.reload.tap { _1.set_discount("percent", "10") }.save! }
    assert_equal [ [ "progress", early.number, 900_00 ] ], credits(final)
    assert_equal [ 0, [ [ early.number, 990_00 ] ] ], [ final.total_cents, client_credits(final) ]
    send!(final)
    assert_equal [ 0, 110_00 ], as_business(@business) { BillingLedger.new(quote: @quote.reload).summary.values_at(:over_billed, :owed) },
                 "$100 and its tax, charged: owed to the client, as nothing is left to bill"
  end

  test "B3: a discount typed on a progress invoice applies to the cash it collected: the final credits only that" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = progress(job)
    as_business(@business) { early.reload.tap { _1.set_discount("percent", "50") }.save! }
    send!(early)
    assert_equal 550_00, early.total_cents
    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final)
    assert_equal [ 550_00, [ [ early.number, 550_00 ] ] ], [ final.total_cents, client_credits(final) ]
    assert_equal 1100_00, early.total_cents + final.total_cents, "each dollar of work billed once: $1,000 and its tax"
  end

  test "B2: a credited progress invoice's own discount can't change on a revision" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    send!(bill_job(complete(job)))
    as_business(@business) { early.reload.revise!(by: @owner) }
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.set_discount("amount", "300") }.save! } }
    assert_match "its amount, discount and tax stay as charged", error.message
  end

  test "S1: a final bill taxed differently from its line's progress is refused, so the credit equals what was charged" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = bill_job(complete(job))
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { final.reload.tap { _1.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "11") ] }.save! } }
    assert_match "Roof is taxed at State 11%, but #{early.number} charged State 10% for it", error.message
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { final.reload.tap { _1.line_items.to_a.sole.taxable = false }.save! } }
    assert_match "Roof is taxed at no tax", error.message
  end

  test "a void invoice keeps its credits when the progress line they pointed at goes" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    as_business(@business) { final.reload.void!(reason: "Redo", by: @owner) }
    as_business(@business) { early.reload.revise!(by: @owner) }
    lower(early, "Roof" => nil)
    assert_equal [ 1, nil ], as_business(@business) { [ final.reload.credits.count, final.credits.first.source_line_item_id ] }, "the void invoice's record stays"
  end

  test "B1: a revision of credited progress that was never sent doesn't count: the final credits what was charged, and discarding it changes nothing" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    as_business(@business) { early.reload.revise!(by: @owner) }
    lower(early, "Roof" => 800)
    final = send!(bill_job(complete(job)))
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final), "the version the client has"
    assert_match "credited on #{final.number}", assert_raises(ActiveRecord::RecordInvalid) { send!(early) }.message
    as_business(@business) { early.reload.discard_revision!(by: @owner) }
    assert_equal [ 550_00, 550_00 ], [ total(early), total(final) ], "$1,100 for $1,100"
  end

  test "B2: Credit from each invoice is what it charged, with mixed taxed and untaxed work" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "g", "Gutters", 1, 500 ] ], tax: "10", untaxed: [ "g" ])
    job = make(r: 1, g: 1)
    taxed = send!(lower(progress(job), "Roof" => 500, "Gutters" => nil))
    untaxed = send!(lower(progress(job), "Roof" => nil, "Gutters" => 500))
    assert_equal [ 550_00, 500_00 ], [ taxed.total_cents, untaxed.total_cents ]
    final = bill_job(complete(job))
    assert_equal [ [ taxed.number, 550_00 ], [ untaxed.number, 500_00 ] ], client_credits(final)
    assert_equal 550_00, final.total_cents
  end

  test "S1: a credited progress invoice can't change what a credited line charges, even by adding another line" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    early = progress(job)
    as_business(@business) { early.reload.tap { _1.set_discount("amount", "100") }.save! }
    send!(early)
    final = send!(bill_job(complete(job)))
    assert_equal [ [ "progress", early.number, 900_00 ] ], credits(final)
    as_business(@business) { early.reload.revise!(by: @owner) }
    error = assert_raises(ActiveRecord::RecordInvalid) do
      as_business(@business) { early.reload.tap { _1.line_items.build(key: "x", name: "Extra", quantity: 1).unit_price = "1000" }.save! }
    end
    assert_match "credited on #{final.number}", error.message
  end

  test "S2: a sent final's revision can't change the tax rate its credits were charged at" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    as_business(@business) { final.reload.revise!(by: @owner) }
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { final.reload.tap { _1.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "11") ] }.save! } }
    assert_match "Roof is taxed at State 11%", error.message
  end

  test "S3: a percent discount is the quote's discount in dollars; a lone job's fixed discount still caps its progress" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], percent: "10")
    early = progress(make(r: 1))
    as_business(@business) do
      assert_nil early.reload.discount_kind, "not copied: it comes off as chosen"
      assert_equal [ 100_00, 900_00 ], [ BillingLedger.new(quote: @quote.reload).quote_discount_cents, early.total_cents ]
    end

    job = as_business(@business) do
      Job.create!(client: @quote.client, property: @quote.property, title: "Fence", discount_kind: "amount", discount_amount_cents: 100_00,
                  line_items_attributes: [ { name: "Fence", quantity: 1, unit_price: 1000 } ])
    end
    lone = progress(job)
    assert_equal 900_00, lone.reload.total_cents
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { lone.reload.tap { _1.set_discount(nil, nil) }.save! } }
    assert_match "Fence: only $900.00 is left to bill.", error.message
  end

  test "a sent final's revision can't take a line below the progress credited on it" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "g", "Gutters", 1, 500 ] ])
    job = make(r: 1, g: 1)
    send!(lower(progress(job), "Roof" => 500, "Gutters" => nil))
    final = send!(bill_job(complete(job)))
    as_business(@business) { final.reload.revise!(by: @owner) }
    error = assert_raises(ActiveRecord::RecordInvalid) do
      as_business(@business) { final.reload.tap { |invoice| invoice.line_items.to_a.find { _1.name == "Roof" }.unit_price = "300" }.save! }
    end
    assert_match "below what it credits", error.message
  end

  test "B-A: a quote line's fixed discount split over two jobs: each job's progress stops at its final's charge" do
    approved_quote([ [ "r", "Roof panels", 2, 500 ] ], line_discounts: { "r" => 100 })
    first, second = make(r: 1), make(r: 1)
    early = progress(first)
    assert_equal 450_00, early.reload.total_cents, "$500 less its $50 of the line's $100"
    send!(early)
    final = send!(bill_job(complete(first)))
    assert_equal [ [ [ "progress", early.number, 450_00 ] ], 0 ], [ credits(final), final.total_cents ]
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
    assert_equal 450_00, send!(bill_job(complete(second))).total_cents
  end

  test "S-A: a progress invoice is taxed as its work is" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    early = progress(make(r: 1))
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "11") ] }.save! } }
    assert_match "must match", error.message
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.line_items.to_a.sole.taxable = false }.save! } }
    assert_match "Roof is taxed as on", error.message
  end

  test "S-B: a revision of progress that lowers it works the final draft out again when it's sent" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final)
    as_business(@business) { early.reload.revise!(by: @owner) }
    lower(early, "Roof" => 300)
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final), "the version the client has, until the revision goes out"
    send!(early)
    assert_equal [ [ "progress", early.number, 300_00 ] ], credits(final)
    assert_match "is on #{final.number}, its final bill (a draft), so nothing is left to bill as progress",
                 assert_raises(ActiveRecord::RecordInvalid) {
                   as_business(@business) { early.reload.revise!(by: @owner) }
                   lower(early, "Roof" => 400)
                 }.message
  end

  test "sending a final works the quote's other drafts out again, so none keeps stale credits" do
    approved_quote([ [ "r", "Roof", 2, 500 ] ])
    early = send!(lower(progress(@quote), "Roof" => 300))
    first, second = [ make(r: 1), make(r: 1) ].map { bill_job(complete(_1)) }
    assert_equal [ [ "progress", early.number, 300_00 ] ], credits(second), "a draft credits it while nothing went out"
    send!(first)
    assert_equal [ [ "progress", early.number, 300_00 ] ], credits(first)
    assert_empty credits(second), "worked out again when the first went out, not on its next save"
    assert_equal 500_00, total(second)
  end

  test "an invoice with nothing due is marked paid at send, and its history says so" do
    approved_quote([ [ "r", "Roof", 1, 500 ] ])
    job = make(r: 1)
    send!(progress(job))
    final = send!(bill_job(complete(job)))
    assert_equal [ "paid", 0 ], [ final.status, final.total_cents ]
    paid = as_business(@business) { final.events.find_by!(kind: "paid") }
    assert_equal [ nil, true ], [ paid.user, paid.data["nothing_due"] ]
    assert_equal "Nothing due: marked paid", ApplicationController.helpers.extend(InvoicesHelper).invoice_event_text(paid).to_s[/\ANothing due: marked paid/]
  end

  test "renaming a sent final's tax rate on a revision says only why" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    as_business(@business) { final.reload.revise!(by: @owner) }
    final = as_business(@business) { final.reload.tap { _1.tax_rate_list = [ Pricing::TaxRate.new(name: "City", percent: "10") ] } }
    assert_not as_business(@business) { final.valid? }
    assert_equal 1, final.errors.count, final.errors.full_messages.to_sentence
  end

  test "a job taxed differently from its quote: quote progress is refused for its line, and a final made after it can be matched" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    as_business(@business) { job.update_columns(tax_rates: [ { "name" => "State", "percent" => "8" } ]) }
    error = assert_raises(WorkBilling::Refused) { progress(@quote) }
    assert_match "Nothing on #{@quote.number} is left to bill as progress", error.message, "its only line is on #{job.number}, at 8%"
    early = progress(job)
    assert_equal "8", as_business(@business) { early.reload.tax_rates.sole["percent"] }

    # After: the progress went out at the quote's 10% and was partly paid, then the job's rate changed.
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    early = send!(lower(progress(@quote), "Roof" => 500))
    as_business(@business) { early.reload.record_payment!(by: @owner, amount: "100", received_on: @business.today, payment_method: "cash") }
    job = make(r: 1)
    as_business(@business) { job.update_columns(tax_rates: [ { "name" => "State", "percent" => "8" } ]) }
    final = bill_job(complete(job))
    assert_empty credits(final), "made as a draft; it credits nothing taxed otherwise"
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(final) }
    assert_match "Roof is taxed at State 8%, but #{early.number} charged State 10% for it. Set this invoice's tax to State 10% to credit it, " \
                 "or refund #{early.number}'s payments and void it first.", error.message
    as_business(@business) { final.reload.tap { _1.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "10") ] }.save! }
    assert_equal [ [ "progress", early.number, 500_00 ] ], credits(final)
    assert_equal 550_00, send!(final).total_cents

    # Progress at two rates (the job re-taxed between them), one partly paid: only the void is left, and it says which.
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10")
    job = make(r: 1)
    paid = send!(lower(progress(job), "Roof" => 300))
    as_business(@business) { paid.reload.record_payment!(by: @owner, amount: "100", received_on: @business.today, payment_method: "cash") }
    retax(job, "8")
    later = send!(lower(progress(job), "Roof" => 200))
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(bill_job(complete(job))) }
    assert_match "Roof is taxed at State 8%, but #{paid.number} charged State 10% for it. Refund #{paid.number}'s payments and void it first.", error.message
    assert later
  end

  test "a staff discount on the last final still takes the rest of the quote's discount; what credits can't take is over-billed" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = make(r: 1)
    early = send!(progress(job))
    assert_equal 900_00, early.total_cents
    final = bill_job(complete(job))
    as_business(@business) { final.reload.tap { _1.set_discount("percent", "20") }.save! }
    assert_equal [ 100_00, [ [ "progress", early.number, 700_00 ] ], 0 ], [ final.reload.quote_discount_share_cents, credits(final), final.total_cents ]
    send!(final)
    assert_equal 200_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
  end

  test "progress stops at a line's value less its part of the discount still to come" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "l", "Labour", 1, 1000 ] ], tax: "10", untaxed: [ "l" ], discount: "400")
    job = make(r: 1, l: 1)
    early = progress(job)
    assert_equal [ 1600_00, 1680_00 ], [ early.reload.subtotal_cents, early.total_cents ], "$800 of each, the roof's taxed"
    lower(early, "Roof" => 1000)
    assert_equal [ 200_00, 1680_00 ], [ early.reload.quote_discount_share_cents, early.total_cents ],
                 "charging the roof in full takes its part of the discount now, so neither line charges more than its final will"
    send!(early)
    final = send!(bill_job(complete(job)))
    assert_equal [ 400_00, 0 ], [ final.quote_discount_share_cents, final.total_cents ]
    assert_equal 1680_00, early.total_cents + final.total_cents, "$2,000 less $400, and 10% on the roof's $800"
  end

  test "the applied quote discount follows the quote's tax mix, so the tax adds up to the quote's whichever invoice takes it" do
    quote_tax = nil
    [ %w[l r], %w[r l] ].each do |order|
      approved_quote([ [ "r", "Roof", 1, 1000 ], [ "l", "Labour", 1, 1000 ] ], tax: "10", untaxed: [ "l" ], discount: "400")
      quote_tax ||= as_business(@business) { @quote.reload.totals.tax_total.cents }
      jobs = order.to_h { [ _1, make(_1.to_sym => 1) ] }
      invoices = order.map { |key| as_business(@business) { Invoice.from_job!(complete(jobs[key]).reload, by: @owner, discount: "all") }.then { send!(_1) } }
      assert_equal 400_00, invoices.sum(&:quote_discount_share_cents)
      assert_equal quote_tax, invoices.sum(&:tax_cents), "#{order.join(" then ")}: $80, as the quote"
      assert_equal 1680_00, invoices.sum(&:total_cents)
    end
    assert_equal 80_00, quote_tax
  end

  test "an amount that isn't one is refused; a huge one is held to what's left" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "b", "Steps", 1, 100 ] ], discount: "300")
    deck = bill_job(complete(make(a: 1)))
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { deck.reload.update!(quote_discount_applied: "abc") } }
    assert_match "isn't an amount", error.message
    as_business(@business) { deck.reload.update!(quote_discount_applied: "99999999999999999999") }
    assert_equal 300_00, deck.reload.quote_discount_share_cents
  end

  def retax(job, *percents) = as_business(@business) { job.update_columns(tax_rates: percents.each_with_index.map { { "name" => _2.zero? ? "State" : "County", "percent" => _1 } }) }

  test "a job taxed otherwise than its quote still gets the whole discount: the part at the quote's rates comes off its lines" do
    [ [ "8", 972_00 ], [ nil, 900_00 ] ].each do |percent, total|
      approved_quote([ [ "r", "Roof", 1, 1000 ] ], tax: "10", discount: "100")
      job = make(r: 1)
      retax(job, *percent)
      final = send!(bill_job(complete(job)))
      assert_equal [ 100_00, total ], [ final.quote_discount_share_cents, final.total_cents ], "taxed at #{percent || "nothing"}"
    end

    approved_quote([ [ "a", "Gate", 1, 100 ], [ "b", "Fence", 1, 1900 ] ], tax: "10", discount: "200")
    gate, fence = make(a: 1), make(b: 1)
    retax(fence, "8")
    first = send!(bill_job(complete(gate)))
    last = send!(bill_job(complete(fence)))
    assert_equal 200_00, first.quote_discount_share_cents + last.quote_discount_share_cents, "none of it lost"

    # Routed, the part comes off lines whose progress credit leaves room first.
    approved_quote([ [ "a", "Roof", 1, 1000 ], [ "b", "Labour", 1, 1000 ] ], tax: "10", untaxed: [ "b" ], discount: "200")
    job = make(a: 1, b: 1)
    retax(job, "8")
    send!(lower(progress(job), "Roof" => 500, "Labour" => 900))
    final = send!(bill_job(complete(job)))
    parts = final.quote_discount_parts.map { [ _1["from"].map { |rate| rate["percent"] }, _1["rates"].map { |rate| rate["percent"] }, _1["cents"] ] }
    assert_equal [ [ [], [], 100_00 ], [ [ "10.0" ], [ "8.0" ], 100_00 ] ], parts.sort
    assert_equal [ [ "progress", 500_00 ], [ "progress", 900_00 ] ], credits(final).map { [ _1[0], _1[2] ] }.sort, "nothing over-billed"
  end

  test "a staff discount on a taxed invoice: the minimum keeps the taxed part there, and the untaxed last invoice takes its own" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "l", "Labour", 1, 500 ] ], tax: "10", untaxed: [ "l" ], discount: "150")
    roof, labour = make(r: 1), make(l: 1)
    first = bill_job(complete(roof))
    as_business(@business) { first.reload.tap { _1.set_discount("percent", "75") }.save! }
    assert_equal 100_00, first.reload.quote_discount_share_cents, "the roof's $100 part, now: no taxed work is left"
    send!(first)
    last = send!(bill_job(complete(labour)))
    assert_equal [ 50_00, 450_00 ], [ last.quote_discount_share_cents, last.total_cents ]
  end

  test "a discount part comes off the base its tax is worked on: Credit from is exactly what the progress charged" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "l", "Labour", 1, 1000 ] ], tax: "10", untaxed: [ "l" ], discount: "200")
    job = make(r: 1, l: 1)
    early = send!(lower(progress(job), "Roof" => 1000, "Labour" => nil))
    assert_equal [ 100_00, 990_00 ], [ early.quote_discount_share_cents, early.total_cents ], "the roof's part, at its rate"
    final = send!(bill_job(complete(job)))
    assert_equal [ [ early.number, 990_00 ] ], client_credits(final)
    assert_equal [ 200_00, 900_00 ], [ final.quote_discount_share_cents, final.total_cents ]
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
  end

  # The reviewer's invariant (owner, 2026-11-23): across a job's progress and final invoices, the
  # client pays the work's value, within a cent per tax rate per invoice, and each "Credit from"
  # equals what that progress invoice charged.
  #
  # Mutation note: dropping a progress invoice's own charge from what's owed (discount_range) and
  # dropping the discount still to come from the progress cap (BillingLedger#discount_left_part)
  # each pass on their own: either one keeps progress within what the final will charge. Only
  # dropping both fails this test. That redundancy is deliberate.
  test "randomized: the work is charged once, less the whole quote discount, and each credit is what was charged" do
    rng = Random.new(Integer(ENV.fetch("PAY08_SEED", 20261123)))
    credited = refused = 0
    credits_of = ->(invoice) { as_business(@business) { invoice.reload.credits.sum(&:amount_cents) } }
    choose = lambda do |invoice| # staff's choice, anywhere from the minimum to the most it can take
      range = as_business(@business) { invoice.reload.quote_discount_range }
      next unless range && rng.rand < 0.7

      at_min = credits_of.(invoice) # made at the minimum
      cents = [ range[:min], range[:min], range[:max], rng.rand(range[:min]..range[:max]) ].sample(random: rng)
      as_business(@business) { invoice.reload.update!(quote_discount_applied: format("%.2f", cents / 100.0)) }
      # More than the minimum, by choice, never cuts a credit (so nothing is over-billed by it).
      assert_operator credits_of.(invoice), :>=, at_min - 1, "#{invoice.number}: #{cents} chosen cuts its credits" if invoice.kind == "work"
    end
    Integer(ENV.fetch("PAY08_SCENARIOS", 45)).times do |n|
      tax = [ nil, "10", "6.25", %w[10 2.5] ].sample(random: rng)
      discount = rng.rand(3)
      lines = Array.new(rng.rand(1..4)) { |i| [ "k#{i}", "Item #{i}", rng.rand(1..3), format("%.2f", rng.rand(20.0..400.0)) ] }
      gross = lines.sum { |_, _, quantity, price| quantity * price.to_d }
      line_discounts = lines.select { rng.rand < 0.3 }.to_h { |key, _, quantity, price| [ key, format("%.2f", quantity * price.to_d * rng.rand(0.05..0.3)) ] }
      line_percents = lines.map(&:first).reject { line_discounts.key?(_1) }.select { rng.rand < 0.35 }.to_h { [ _1, format("%.2f", rng.rand(5.0..45.0)) ] }
      inclusive = tax.present? && rng.rand < 0.2
      untaxed = lines.map(&:first).select { rng.rand < 0.3 }
      approved_quote(lines, quick: true, tax:, inclusive:, untaxed:, percent: (rng.rand(5..20).to_s if discount == 1),
                            discount: (format("%.2f", gross * rng.rand(0.02..0.15)) if discount == 2), line_discounts:, line_percents:)
      # Two jobs share the first line when it has more than one to do; a job for each line; a
      # taxed-only job and an untaxed-only one; or one job. Sometimes one is taxed otherwise.
      split = lines.first[2] > 1 && rng.rand < 0.3 ? rng.rand(1...lines.first[2]) : nil
      picks = lines.to_h { |key, _, quantity, _| [ key.to_sym, quantity ] }
      by_tax = picks.keys.partition { !untaxed.include?(_1.to_s) }.reject(&:empty?)
      direct = rng.rand < 0.12 # billed straight from the quote, with no job
      jobs = if direct then []
      elsif split then [ make(**picks, k0: split), make(k0: picks[:k0] - split) ]
      elsif by_tax.many? && rng.rand < 0.4 then by_tax.map { |keys| make(**picks.slice(*keys)) }
      elsif lines.many? && rng.rand < 0.4 then picks.map { |key, quantity| make(key => quantity) }
      else [ make(**picks) ]
      end
      retaxed = tax.present? && rng.rand < 0.2
      retax(jobs.sample(random: rng), *[ [ "8" ], [], %w[8 1] ].sample(random: rng)) if retaxed && jobs.any?
      sources = jobs + (rng.rand < 0.25 ? [ @quote ] : []) # progress from the quote, too
      progress_sent = sources.shuffle(random: rng).flat_map do |source|
        Array.new(rng.rand(0..2)).filter_map do
          invoice = progress(source)
          amounts = as_business(@business) { invoice.reload.line_items.to_h { [ _1.name, (_1.line_amount_cents * rng.rand(0.2..1.0) / 100).round(2).to_d.to_s("F") ] } }
          if source.is_a?(Job) && rng.rand < 0.25 # raised to the work's full value: past what's left, if a discount is still to come
            amounts = as_business(@business) { invoice.reload.line_items.to_h { [ _1.name, (JobLineItem.find(_1.job_line_item_id).line_amount_cents / 100.0).round(2).to_s ] } }
          end
          lower(invoice, amounts) if rng.rand < 0.6 # else as made: all that's left
          as_business(@business) { invoice.reload.tap { _1.set_discount("percent", %w[10 50].sample(random: rng)) }.save! } if rng.rand < 0.3
          choose.(invoice)
          send!(invoice)
        rescue WorkBilling::Refused, ActiveRecord::RecordInvalid
          nil
        end
      end
      if progress_sent.any? && rng.rand < 0.2 # a void before the work is billed: neither paid nor credited, its discount back
        as_business(@business) { progress_sent.pop.reload.void!(reason: "Wrong", by: @owner) }
      end
      staff_off = shortfall = false
      over_checks = []
      one_group = tax.nil? || untaxed.empty? || untaxed.size == lines.size
      finals = direct ? [ send!(bill_quote) ] : []
      finals += jobs.shuffle(random: rng).each_with_index.map do |job, index|
        done = {}
        if rng.rand < (progress_sent.any? ? 0.3 : 0.15) # less done than quoted: the discount scales once it's all done (B13: after progress, more often)
          item = as_business(@business) { job.reload.line_items.select { _1.quantity.to_d > 1 }.first }
          (done[item.name] = rng.rand(1...item.quantity.to_i)) && shortfall = true if item
        end
        over, rates_over = as_business(@business) { BillingLedger.new(quote: @quote.reload).then { |l| [ l.over_billed_cents, l.over_billed.flat_map { l.rates_of(_1) }.uniq ] } }
        final = bill_job(complete(job, done))
        if progress_sent.any? && rng.rand < 0.15 # a void while this draft is open: the draft is worked out again
          unless as_business(@business) { progress_sent.last.reload.credited_later? }
            voided = progress_sent.pop
            as_business(@business) { voided.reload.void!(reason: "Wrong", by: @owner) }
          end
          stored = as_business(@business) { final.reload.then { [ _1.quote_discount_share_cents, _1.quote_discount_parts, _1.credits.map(&:amount_cents) ] } }
          fresh = as_business(@business) { final.reload.tap(&:save!).reload.then { [ _1.quote_discount_share_cents, _1.quote_discount_parts, _1.credits.map(&:amount_cents) ] } }
          assert_equal fresh, stored, "scenario #{n}: a void works the open draft out again"
        end
        # The minimum is the real lower bound: what the work left after it can't take, after its credits.
        if one_group && !staff_off
          as_business(@business) do
            range = final.reload.quote_discount_range
            ledger = BillingLedger.for(final)
            later = ledger.work_left_cents(billed: final.current_line_items.select(&:final)) - (ledger.uncredited_cents - final.credits.sum(&:amount_cents))
            assert_equal [ range[:left] - later.clamp(0..), 0 ].max.clamp(0, range[:max]), range[:min], "scenario #{n}: #{final.number}'s minimum" if range && final.quote_discount_share_cents == range[:min]
          end
        end
        if rng.rand < 0.3 # a staff discount typed on the final
          staff_off = true
          as_business(@business) { final.reload.tap { _1.set_discount("percent", %w[5 20 90].sample(random: rng)) }.save! }
        end
        choose.(final)
        # B13's shape: all of the discount on a job done short after its progress, so a later
        # invoice charges some back while the progress is over-billed.
        as_business(@business) { final.reload.update!(quote_discount_applied: "all") } if done.any? && progress_sent.any? && rng.rand < 0.5
        final = begin
          send!(final)
        rescue ActiveRecord::RecordInvalid => error # R4: too little left for the quote's discount
          raise unless error.message.include?("too little to take the rest")

          refused += 1
          as_business(@business) { final.reload.tap { _1.set_discount(nil, nil) }.save! }
          send!(final) # a shortfall alone never refuses: the last invoice takes what fits (owner, 2026-11-24)
        end
        over_checks << [ final, over, rates_over ] if over.positive?
        # Needs first: no group is left with more of the discount than its own work left can take.
        if index < jobs.size - 1 && !staff_off && !shortfall && !retaxed
          as_business(@business) do
            later = BillingLedger.new(quote: @quote.reload)
            work, owed = later.work_left_by_group, later.uncredited_by_group
            later.net_outstanding_by_group.each { |group, cents| assert_operator cents, :<=, [ work[group] - owed[group], 0 ].max + Array(tax).size * (index + 2), "scenario #{n}: #{group.map(&:percent)}'s part after #{final.number}" }
          end
        end
        next final unless rng.rand < 0.15 # voided and billed again: its credits and discount come back on the new one

        as_business(@business) { final.reload.void!(reason: "Redo", by: @owner) }
        send!(bill_job(job))
      end
      invoices = progress_sent + finals
      rates = Array(tax)
      slack = rates.size * invoices.size
      ledger = as_business(@business) { BillingLedger.new(quote: @quote.reload) }
      quote_discount = as_business(@business) { ledger.quote_discount_cents }
      # All of it, charge-backs counted against it and what the last couldn't take as given.
      applied = as_business(@business) { finals.sum { |final| final.reload.quote_discount_parts.sum { _1["cents"].to_i } } }
      assert_equal quote_discount, applied, "scenario #{n}: the work's invoices give the whole quote discount (#{as_business(@business) { ledger.unused_discount_cents }} not used)"
      as_business(@business) { invoices.each(&:reload) }
      assert invoices.all? { _1.total_cents >= 0 }, "scenario #{n}: no invoice charges less than nothing"
      # Each quote line's fixed discount is shared by quantity billed, exactly.
      as_business(@business) do
        @quote.line_items.select { _1.discount_kind == "amount" }.each do |item|
          bills = finals.flat_map(&:line_items).select { _1.final && _1.quote_line_item_id == item.id }
          share = [ (item.discount_amount_cents * bills.sum { _1.quantity.to_d } / item.quantity.to_d).round(0, Money::ROUNDING).to_i, item.discount_amount_cents ].min
          assert_equal share, bills.sum(&:discount_share_cents), "scenario #{n}: #{item.name}'s share"
        end
        # A percent discount too (B16, owner 2026-11-24): the bills of a line, however split, take
        # exactly the quote line's discount once all of it is billed.
        @quote.line_items.select { _1.discount_kind == "percent" }.each do |item|
          bills = finals.flat_map(&:line_items).select { _1.final && _1.quote_line_item_id == item.id }
          next unless bills.sum { _1.quantity.to_d } == item.quantity.to_d

          expected = item.line_amount_cents - BillingLedger.subtotal_cents(item, @quote.currency)
          assert_equal expected, bills.sum { _1.line_amount_cents - BillingLedger.subtotal_cents(_1, @quote.currency) }, "scenario #{n}: #{item.name}'s percent discount over its bills"
        end
      end
      # Over-billing is credited on the next invoice, as far as it can take it (what it charges
      # after its own progress credits, and each rate's base for taxed progress).
      over_checks.each do |final, over, rates_over|
        as_business(@business) do
          credits = final.credits.to_a
          taken = credits.select { _1.kind == "over_billed" }.sum(&:amount_cents)
          room = final.send(:net_by_line).values.sum + final.quote_discount_charge_back.cents - credits.select { _1.kind == "progress" }.sum(&:amount_cents) # B13: the charge-back takes it too
          bases = final.send(:tax_bases)
          credits.select { _1.kind == "progress" }.each { |credit| credit.tax_rate_list.each { bases[_1] -= credit.amount_cents } }
          cap = [ over, room, *rates_over.map { bases[_1] } ].min
          assert_operator taken, :>=, cap - slack, "scenario #{n}: #{final.number} credits what was over-billed" unless inclusive
        end
      end
      # Before tax: the finals' work less their discounts (the quote's included), however much was
      # billed early, at whatever discount; over-billing left over would show here.
      worth = as_business(@business) { finals.sum { _1.totals(credits: false).then { |t| (t.subtotal - t.discount).cents } } }
      over_billed = as_business(@business) { ledger.over_billed_cents }
      assert_operator over_billed, :<=, slack, "scenario #{n}: nothing over-billed without a staff discount or less work done" unless staff_off || shortfall
      worth += over_billed
      paid = invoices.sum { inclusive ? _1.total_cents : _1.total_cents - _1.tax_cents }
      assert_in_delta worth, paid, slack, "scenario #{n}: the work's value, less the discounts, before tax"
      # Tax is worked on each line's own rates, after what comes off it (R3, owner 2026-11-23).
      unless inclusive
        as_business(@business) do
          # Every invoice is taxed on the quote's net base so far (credits off), less the tax charged
          # (owner, 2026-11-24): what went out before it is as it was when it went out.
          invoices.each do |invoice|
            net = invoice.send(:net_by_line)
            # A charge-back is taxed at the rates its discount came off (owner, 2026-11-24).
            backs = invoice.quote_discount_parts.select { !_1["key"] && !_1["owed"] }.flat_map { BillingLedger.rates_from(_1["rates"]) }
            expected = (invoice.tax_rate_list | backs).sum do |rate|
              back = invoice.quote_discount_parts.select { !_1["key"] && !_1["owed"] && BillingLedger.rates_from(_1["rates"]).include?(rate) }.sum { _1["cents"].to_i }
              base = net.sum { |line, cents| invoice.send(:rates_for, line).include?(rate) ? cents : 0 } - back -
                     invoice.credits.select { _1.pre_tax? && _1.tax_rate_list.include?(rate) }.sum(&:amount_cents)
              prior_base, prior_tax = invoice.prior_tax.fetch(rate) { [ Money.zero(invoice.currency), Money.zero(invoice.currency) ] }.map(&:cents)
              [ ((prior_base + base) * rate.percent / 100).round(0, Money::ROUNDING).to_i - prior_tax, 0 ].max # never below zero (B19)
            end
            assert_equal expected, invoice.tax_cents, "scenario #{n}: #{invoice.number}'s tax on its lines' own rates"
          end
          # The true cumulative tax plus what's owed back is what was charged, at each rate (B19).
          charged = Hash.new { |hash, rate| hash[rate] = [ 0, 0 ] }
          invoices.each { |invoice| invoice.charged_net_by_rate.each { |rate, (base, tax)| charged[rate][0] += base; charged[rate][1] += tax } }
          over = BillingLedger.new(quote: @quote.reload).tax_over_charged_by_rate
          charged.each do |rate, (base, tax)|
            assert_equal tax, (base * rate.percent / 100).round(0, Money::ROUNDING).to_i + over.fetch(rate, 0), "scenario #{n}: true tax + owed = charged at #{rate.percent}%"
          end
        end
      end
      unless staff_off || inclusive || retaxed || shortfall # the tax adds up to the quote's
        quote_tax = as_business(@business) { @quote.reload.totals.tax_total.cents }
        assert_in_delta quote_tax, invoices.sum(&:tax_cents), slack + rates.size, "scenario #{n}: tax as the quote's"
        # Progress and the finals charge the tax on the whole job, rounded once, however many finals (owner, 2026-11-24).
        if progress_sent.sum { _1.line_items.size } == as_business(@business) { finals.sum { _1.credits.size } }
          assert_equal quote_tax, invoices.sum(&:tax_cents), "scenario #{n}: tax as the quote's, to the cent"
          assert_equal as_business(@business) { @quote.reload.total_cents }, invoices.sum(&:total_cents), "scenario #{n}: billed = the quote's total, to the cent" if over_billed.zero? && invoices.none? { |i| i.quote_discount_parts.any? { _1["owed"] } } # what's owed is refunded by hand
        end
      end
      # Progress never charges a line more than its final does (owner, 2026-11-23), before any
      # staff discount on the final, when the work was done as quoted.
      unless staff_off || shortfall
        as_business(@business) do
          final_net = finals.to_h { |final| [ final, final.send(:net_by_line) ] }.flat_map { |_, nets| nets.map { |line, cents| [ line.job_line_item_id || [ :quote, line.quote_line_item_id ], cents ] } }.to_h
          progress_sent.each do |early|
            charged = early.charged_by_key
            early.line_items.each do |line|
              next unless (limit = final_net[line.job_line_item_id || [ :quote, line.quote_line_item_id ]])

              assert_operator charged[line.key].to_i, :<=, limit + 1, "scenario #{n}: #{early.number}'s #{line.name} charges no more than its final"
            end
          end
        end
      end
      # The client's "Credit from" rows add up to what the credits take off, to the cent.
      as_business(@business) { finals.each { |final| assert_equal (final.totals(credits: false).total - final.totals.total).cents, final.client_credits.sum { _2.cents }, "scenario #{n}: #{final.number}'s Credit from rows" if final.credits.any?(&:pre_tax?) } }
      shown = finals.flat_map { client_credits(_1) }.group_by(&:first).transform_values { _1.sum(&:last) }
      fully = as_business(@business) { progress_sent.select { |p| InvoiceCredit.counted.where(source_invoice_id: p.id).sum(:amount_cents) == p.charged_by_key.values.sum } }
      fully.each do |early|
        assert_equal early.total_cents, shown[early.number].to_i, "scenario #{n}: Credit from #{early.number} is exactly what it charged (B14)"
      end
      credited += 1 if shown.any?
      @client ||= as_business(@business) { @quote.client }
    end
    assert_operator credited, :>, 15, "most scenarios bill progress first"
    puts "PAY-08 randomized: #{refused} refused till the staff discount came off (R4)" if ENV["PAY08_SCENARIOS"]
  end

  test "credit order: a line's own progress, then its quote line's, then over-billing; each capped by the bill" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ], [ "g", "Gutters", 1, 300 ], [ "s", "Shed", 1, 200 ] ])
    shed_job = make(s: 1)
    shed_early = send!(lower(progress(shed_job), "Shed" => 200))
    trees_early = send!(lower(progress(@quote), "Tree removal" => 100, "Gutters" => nil))
    job = make(t: 10, g: 1)
    own = send!(lower(progress(job), "Tree removal" => 400, "Gutters" => nil))
    as_business(@business) { shed_job.reload.cancel!(by: @owner, reason: "Not now", notify_client: false) }
    # The shed's progress is on its quote line now, with nothing left to bill once a job that
    # takes it does none of it and is billed ($0).
    send!(bill_job(complete(make(s: 1), "Shed" => 0)))

    final = bill_job(complete(job))
    assert_equal [ [ "progress", own.number, 400_00 ], [ "progress", trees_early.number, 100_00 ], [ "over_billed", shed_early.number, 200_00 ] ],
                 credits(final).first(3)
    assert_equal 1300_00 - 700_00, final.total_cents
  end

  test "a quote line's fixed discount is shared by quantity billed; the quote's comes off as chosen, the last taking the rest" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ], line_discounts: { "t" => 50 })
    first = send!(bill_job(complete(make(t: 3))))
    assert_equal 15_00, as_business(@business) { first.line_items.sole.discount_share_cents }, "min($50, round($50 × 3 ÷ 10))"
    second = send!(bill_job(complete(make(t: 7))))
    assert_equal 35_00, as_business(@business) { second.line_items.sole.discount_share_cents }

    approved_quote([ [ "a", "A", 1, 100 ], [ "b", "B", 1, 100 ], [ "c", "C", 1, 100 ] ], discount: "150")
    a = send!(bill_job(complete(make(a: 1))))
    b = as_business(@business) { Invoice.from_job!(complete(make(b: 1)).reload, by: @owner, discount: "all") }
    assert_equal [ 0, 100_00 ], [ a.quote_discount_share_cents, b.reload.quote_discount_share_cents ], "Apply later, then all this one can take"
    send!(b)
    c = send!(bill_job(complete(make(c: 1))))
    assert_equal 50_00, c.quote_discount_share_cents
  end

  test "the minimum: what the work left can't absorb comes off now; a void returns what was applied" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "b", "Steps", 1, 100 ] ], discount: "300")
    deck = bill_job(complete(make(a: 1)))
    range = as_business(@business) { deck.reload.quote_discount_range }
    assert_equal({ left: 300_00, min: 200_00, max: 300_00, applied: 200_00, work_left: 100_00, short: false }, range.slice(:left, :min, :max, :applied, :work_left, :short))
    assert_equal 200_00, deck.quote_discount_share_cents, "only $100 of work is left to take the rest"
    send!(deck)
    as_business(@business) { deck.reload.void!(reason: "Redo", by: @owner) }
    assert_equal 300_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).outstanding_cents }
  end

  test "by choice a final applies no more than leaves its progress credit whole; what must go now still goes" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "b", "Steps", 1, 1000 ] ], discount: "500")
    deck = make(a: 1)
    send!(lower(progress(deck), "Deck" => 700))
    final = as_business(@business) { Invoice.from_job!(complete(deck).reload, by: @owner, discount: "all") }
    assert_equal [ 300_00, 700_00, 0 ], [ final.reload.quote_discount_share_cents, credits(final).sum { _1[2] }, final.total_cents ], "$1,000 − the $700 credit"
    send!(final)
    steps = send!(bill_job(complete(make(b: 1))))
    assert_equal [ 200_00, 800_00 ], [ steps.quote_discount_share_cents, steps.total_cents ], "the last takes the rest"
  end

  test "R4: a staff discount on the last final that leaves too little for the quote's discount can't be sent until it's lowered" do
    approved_quote([ [ "a", "A", 1, 500 ], [ "b", "B", 1, 500 ] ], discount: "100")
    a, b = make(a: 1), make(b: 1)
    send!(bill_job(complete(a)))
    last = bill_job(complete(b))
    as_business(@business) { last.reload.tap { _1.set_discount("percent", "90") }.save! }
    range = as_business(@business) { last.reload.quote_discount_range }
    assert_equal({ left: 100_00, min: 50_00, max: 50_00, applied: 50_00, short: true }, range.slice(:left, :min, :max, :applied, :short))
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(last) }
    assert_includes error.message, "charges too little to take the rest of the quote's discount ($100.00 left, $50.00 fits). Lower its own discount to send it."
    as_business(@business) { last.reload.tap { _1.set_discount("percent", "80") }.save! }
    assert_equal [ 100_00, 0 ], [ send!(last).quote_discount_share_cents, last.total_cents ]
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).outstanding_cents }
  end

  test "B6: quote progress, then a job at its minimum: the minimum comes off where the credits leave room, so nothing is over-billed" do
    approved_quote([ [ "x", "Mulch", 6, 100 ], [ "y", "Edging", 1, 300 ] ], discount: "90")
    j1, j2 = make(x: 5, y: 1), make(x: 1)
    early = send!(progress(@quote))
    assert_equal 810_00, early.total_cents
    first = bill_job(complete(j1))
    assert_equal [ 30_00, 30_00 ], [ first.reload.quote_discount_share_cents, as_business(@business) { first.quote_discount_range }[:min] ]
    assert_equal [ 770_00, 0 ], [ credits(first).sum(&:last), first.total_cents ], "Edging's $30 of room takes it; Mulch's $500 credit stays whole"
    send!(first)
    last = send!(bill_job(complete(j2)))
    assert_equal [ 60_00, [ [ "progress", early.number, 40_00 ] ], 0 ], [ last.quote_discount_share_cents, credits(last), last.total_cents ]
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }, "$810 billed in all"
  end

  test "PQ3: a taxed-only invoice never carries the untaxed part, in either order" do
    [ %i[a b], %i[b a] ].each do |order|
      approved_quote([ [ "a", "Roof", 1, 100 ], [ "b", "Labour", 1, 100 ] ], tax: "10", untaxed: [ "b" ], discount: "50")
      jobs = { a: make(a: 1), b: make(b: 1) }
      invoices = order.to_h { |key| [ key, send!(as_business(@business) { Invoice.from_job!(complete(jobs[key]).reload, by: @owner, discount: "all") }) ] }
      assert_equal [ 25_00, 7_50, 82_50 ], [ invoices[:a].quote_discount_share_cents, invoices[:a].tax_cents, invoices[:a].total_cents ], "billed #{order.join(", then ")}"
      assert_equal [ 25_00, 0, 75_00 ], [ invoices[:b].quote_discount_share_cents, invoices[:b].tax_cents, invoices[:b].total_cents ]
    end
  end

  test "R3: a re-taxed job's part comes off its own lines, at its own rates; the client gets the whole discount" do
    approved_quote([ [ "a", "Roof", 1, 1000 ], [ "b", "Deck", 1, 1000 ] ], tax: "10", discount: "200")
    roof, deck = make(a: 1), make(b: 1)
    retax(roof, "8")
    first = bill_job(complete(roof))
    assert_equal 0, as_business(@business) { first.reload.quote_discount_range }[:min], "the deck's work can still take it all"
    as_business(@business) { first.reload.tap { _1.quote_discount_applied = "100" }.save! }
    assert_equal [ 100_00, 72_00, 972_00 ], [ send!(first).quote_discount_share_cents, first.tax_cents, first.total_cents ], "8% of $900"
    last = send!(bill_job(complete(deck)))
    assert_equal [ 100_00, 90_00, 990_00 ], [ last.quote_discount_share_cents, last.tax_cents, last.total_cents ]
  end

  test "R5: a shortfall scales the quote's discount to the quoted value done; the rest is not used" do
    [ [ { discount: "100" }, 60_00 ], [ { percent: "10" }, 60_00 ] ].each do |kind, scaled|
      approved_quote([ [ "t", "Tree removal", 10, 100 ] ], **kind)
      job = make(t: 10)
      final = bill_job(complete(job, "Tree removal" => 6))
      ledger = as_business(@business) { BillingLedger.for(final.reload) }
      assert_equal [ scaled, 100_00 - scaled, true ], [ ledger.quote_discount_cents, ledger.unused_discount_cents, ledger.all_done? ]
      assert_equal [ scaled, 600_00 - scaled ], [ send!(final).quote_discount_share_cents, final.total_cents ], kind.inspect
      assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).outstanding_cents }, "not outstanding: nothing is short"
    end

    approved_quote([ [ "t", "Tree removal", 10, 100 ], [ "s", "Stump grinding", 3, 100 ] ], discount: "130")
    first = send!(bill_job(complete(make(t: 10))))
    assert_equal [ 0, 130_00 ], [ first.quote_discount_share_cents, as_business(@business) { BillingLedger.new(quote: @quote.reload).outstanding_cents } ], "not done: all of it still to come"
    last = bill_job(complete(make(s: 3), "Stump grinding" => 2))
    assert_equal [ 120_00, 10_00 ], [ last.reload.quote_discount_share_cents, as_business(@business) { BillingLedger.for(last).unused_discount_cents } ], "$130 × $1,200 ÷ $1,300"
    assert_equal 80_00, send!(last).total_cents
  end

  test "direct billing, no jobs: the draft's share is the share sent, the whole discount" do
    [ [ { percent: "10" }, 10_00 ], [ { discount: "15" }, 15_00 ] ].each do |kind, share|
      approved_quote([ [ "a", "A", 1, 100 ] ], **kind)
      draft = bill_quote
      assert_equal [ share, share ], [ draft.reload.quote_discount_share_cents, as_business(@business) { draft.quote_discount_range }[:applied] ]
      assert_equal [ share, 100_00 - share ], [ send!(draft).quote_discount_share_cents, draft.total_cents ], kind.inspect
      assert_equal [ 0, 0 ], as_business(@business) { BillingLedger.new(quote: @quote.reload).then { [ _1.outstanding_cents, _1.unused_discount_cents ] } }
    end
  end

  test "shortfall after the discount was applied early: the last invoice charges the extra back, at its rates" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ], tax: "10", discount: "100")
    first = send!(as_business(@business) { Invoice.from_job!(complete(make(t: 5)).reload, by: @owner, discount: "all") })
    assert_equal [ 100_00, 40_00 ], [ first.quote_discount_share_cents, first.tax_cents ]
    last = send!(bill_job(complete(make(t: 5), "Tree removal" => 1)))
    assert_equal [ 0, 40_00, 14_00, 154_00 ], [ last.quote_discount_share_cents, as_business(@business) { last.quote_discount_charge_back.cents }, last.tax_cents, last.total_cents ],
                 "$100 scaled to $60: $40 back, taxed as it came off"
    assert_equal 54_00, first.tax_cents + last.tax_cents, "10% of $600 − $60"
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).net_outstanding_cents }
    get_client = as_business(@business) { ApplicationController.render(partial: "admin/quotes/totals", locals: { quote: last.reload, client: true }) }
    assert_match(/Quote discount adjusted for work not done.*\+\$40\.00/m, get_client)
  end

  test "shortfall to nothing: the last invoice takes what fits, down to $0, and the rest is owed to the client" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "s", "Stump grinding", 3, 100 ] ], discount: "130")
    send!(bill_job(complete(make(a: 1))))
    last = bill_job(complete(make(s: 3), "Stump grinding" => 0))
    range = as_business(@business) { last.reload.quote_discount_range }
    assert_equal({ left: 100_00, applied: 0, owed: 100_00, short: false }, range.slice(:left, :applied, :owed, :short), "$130 × $1,000 ÷ $1,300, none fits")
    assert_equal 0, send!(last).total_cents
    assert_equal [ 0, 100_00, 30_00, { billed: 0, credited: 0, over_billed: 0, owed: 100_00 } ],
                 as_business(@business) { BillingLedger.new(quote: @quote.reload).then { [ _1.outstanding_cents, _1.discount_owed_cents, _1.unused_discount_cents, _1.summary ] } }
  end

  test "over-billing is credited on the next invoice while there's work left to bill; after that it's owed to the client" do
    approved_quote([ [ "r", "Roof", 1, 1000 ], [ "g", "Gutters", 1, 500 ] ], tax: "10")
    roof, gutters = make(r: 1), make(g: 1)
    send!(progress(roof))
    final = bill_job(complete(roof))
    as_business(@business) { final.reload.tap { _1.set_discount("percent", "20") }.save! }
    send!(final)
    summary = -> { as_business(@business) { BillingLedger.new(quote: @quote.reload).summary } }
    assert_equal({ over_billed: 220_00, owed: 0 }, summary.().slice(:over_billed, :owed), "the gutters are still to bill")
    last = bill_job(complete(gutters))
    as_business(@business) { last.reload.tap { _1.set_discount("percent", "90") }.save! }
    assert_equal [ [ "over_billed", 50_00 ] ], credits(send!(last)).map { [ _1[0], _1[2] ] }, "the next invoice credits what it can"
    assert_equal({ over_billed: 0, owed: 165_00 }, summary.().slice(:over_billed, :owed), "the rest, with its tax: nothing is left to credit it on")
  end

  test "a shortfall's discount is rounded once, then spread by largest remainder" do
    approved_quote([ [ "a", "A", 3, "33.33" ], [ "b", "B", 7, "14.29" ] ], untaxed: [ "b" ], tax: "10", percent: "7")
    job = make(a: 3, b: 7)
    final = bill_job(complete(job, "A" => 2, "B" => 5))
    ledger = as_business(@business) { BillingLedger.for(final.reload) }
    expected = (ledger.full_quote_discount_cents * (6666 + 7145) / 20002r).round
    assert_equal expected, ledger.quote_discount_cents, "D × quoted value done ÷ quoted value"
    assert_equal expected, ledger.discount_mix.values.sum
    assert_equal({ a: 4, b: 3, c: 3 }, BillingLedger.largest_remainder(10, { a: 1, b: 1, c: 1 }))
    assert_equal({ a: 1, b: 2 }, BillingLedger.largest_remainder(3, { a: 1.4, b: 1.6 }))
  end

  test "B9: a one-cent discount scaled to nothing: the last invoice charges it back, no group missing" do
    approved_quote([ [ "a", "A", 1, "0.01" ], [ "b", "B", 3, "0.01" ] ], tax: "10", discount: "0.01")
    j1, j2 = make(a: 1), make(b: 3)
    first = send!(as_business(@business) { Invoice.from_job!(complete(j1).reload, by: @owner, discount: "all") })
    assert_equal 1, first.quote_discount_share_cents
    last = send!(bill_job(complete(j2, "B" => 1)))
    ledger = as_business(@business) { BillingLedger.new(quote: @quote.reload) }
    assert_equal as_business(@business) { ledger.quote_discount_cents }, [ first, last ].sum { |invoice| invoice.reload.quote_discount_parts.sum { _1["cents"].to_i } }
    assert_equal 0, as_business(@business) { ledger.net_outstanding_by_group[[ Pricing::TaxRate.new(name: "Nobody", percent: "1") ]] }, "an unknown group is 0, not nil"
  end

  test "B10: a shortfall in one group never gives another group more than its full part" do
    approved_quote([ [ "k0", "Item 0", 2, "72834.68" ], [ "k1", "Item 1", 3, "333.33" ], [ "k2", "Item 2", 2, "244.00" ], [ "k3", "Item 3", 10, "728.00" ],
                     [ "k4", "Item 4", 3, "333.33" ], [ "k5", "Item 5", 3, "0.01" ], [ "k6", "Item 6", 1, "477.00" ] ],
                   tax: %w[6.25 2.5], discount: "9065.25", untaxed: %w[k1 k3 k5 k6], line_discounts: { "k0" => "14353.20", "k6" => "48.43" })
    taxed, untaxed = make(k0: 2, k2: 2, k4: 3), make(k1: 3, k3: 10, k5: 3, k6: 1)
    retax(untaxed, "8")
    send!(lower(progress(@quote), "Item 0" => "122904.10", "Item 2" => "456.74", "Item 4" => "935.93"))
    first = send!(bill_job(complete(untaxed, "Item 6" => 0)))
    complete(taxed)
    last = send!(bill_quote)
    as_business(@business) do
      ledger = BillingLedger.new(quote: @quote.reload)
      assert_operator first.quote_discount_share_cents + last.quote_discount_share_cents, :<=, ledger.full_quote_discount_cents, "never more than the quote's discount"
      assert_equal ledger.quote_discount_cents, [ first, last ].sum { |invoice| invoice.reload.quote_discount_parts.sum { _1["cents"].to_i } }
      assert_equal 850738, ledger.discount_mix[ledger.group_of(@quote.line_items.first)], "the taxed work was all done: its whole part"
    end
  end

  test "B11: once the work left is needed for the discount, progress isn't offered and says why" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "b", "Steps", 1, 100 ] ], discount: "300")
    deck, steps = make(a: 1), make(b: 1)
    assert_equal 200_00, send!(bill_job(complete(deck))).quote_discount_share_cents, "the minimum"
    assert as_business(@business) { BillingLedger.new(quote: @quote.reload).progress_blocked? }
    [ steps, @quote ].each do |source|
      error = assert_raises(WorkBilling::Refused) { progress(source) }
      assert_equal "Nothing is left to bill as progress: the work left is needed for the quote's discount.", error.message
    end
  end

  test "undoing progress credited on another job's final: void that one, then refund and void the progress" do
    approved_quote([ [ "a", "Roof", 1, 1000 ], [ "b", "Gutters", 1, 500 ] ], tax: "10")
    roof, gutters = make(a: 1), make(b: 1)
    early = send!(lower(progress(@quote), "Roof" => 500, "Gutters" => 200))
    as_business(@business) { early.reload.record_payment!(by: @owner, amount: "100", received_on: @business.today, payment_method: "cash") }
    credited = send!(bill_job(complete(roof)))
    retax(gutters, "8")
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(bill_job(complete(gutters))) }
    assert_includes error.message, "Gutters is taxed at State 8%, but #{early.number} charged State 10% for it. Set this invoice's tax to State 10% to credit it, " \
                                   "or void #{credited.number}, then refund #{early.number}'s payments and void it first."
  end

  test "progress already billed: what's left of each line is its value less its part of the discount, less that progress" do
    approved_quote([ [ "a", "Roof", 1, 1000 ], [ "b", "Gutters", 1, 1000 ] ], discount: "200")
    send!(lower(progress(@quote), "Roof" => 500, "Gutters" => nil))
    again = progress(@quote)
    assert_equal [ 400_00, 900_00 ], as_business(@business) { again.reload.current_line_items.map(&:line_amount_cents) }, "quote lines: $1,000 − $100 − $500, and $1,000 − $100"

    approved_quote([ [ "a", "Roof", 1, 1000 ], [ "b", "Gutters", 1, 1000 ] ], discount: "200")
    job = make(a: 1, b: 1)
    send!(lower(progress(job), "Roof" => 500, "Gutters" => nil))
    again = progress(job)
    assert_equal [ 400_00, 900_00 ], as_business(@business) { again.reload.current_line_items.map(&:line_amount_cents) }, "job lines, the same"
    assert_raises(ActiveRecord::RecordInvalid) { lower(again, "Roof" => "400.01") }

    approved_quote([ [ "a", "Roof", 2, 500 ], [ "b", "Gutters", 1, 1000 ] ], discount: "200")
    half = make(a: 1)
    make(a: 1, b: 1)
    assert_equal [ 450_00 ], as_business(@business) { progress(half).reload.current_line_items.map(&:line_amount_cents) }, "half the roof: $500 − half its $100 part"
  end

  test "B13: over-billing comes off a charge-back too: a client owed more than an invoice charges is never billed" do
    [ [ nil, [], 0 ], [ "10", [], 0 ], [ %w[10 2.5], [], 0 ] ].each do |tax, untaxed, total|
      approved_quote([ [ "a", "A", 2, 1000 ], [ "b", "B", 1, 100 ] ], tax:, untaxed:, discount: "900")
      j1, j2 = make(a: 2), make(b: 1)
      early = send!(progress(j1))
      first = send!(bill_job(complete(j1, "A" => 1)))
      over = as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
      last = send!(bill_job(complete(j2)))
      as_business(@business) do
        back = last.quote_discount_charge_back.cents
        assert_operator back, :>, 0, "taxed at #{tax.inspect}: the discount scaled down, so some comes back"
        taken = last.credits.select { _1.kind == "over_billed" }.sum(&:amount_cents)
        assert_equal [ total, [ over, 100_00 + back ].min ], [ last.total_cents, taken ], "taxed at #{tax.inspect}: it credits against its whole charge, the charge-back too"
        ledger = BillingLedger.new(quote: @quote.reload)
        paid = [ early, first, last ].sum { _1.reload.total_cents - _1.tax_cents }
        assert_equal 1100_00 - ledger.quote_discount_cents + ledger.over_billed_cents, paid, "the work less the scaled discount, plus what's owed"
        shown = last.client_credits.sum { _2.cents }
        assert_equal (last.totals(credits: false).total - last.totals.total).cents, shown, "the client's Credit from rows add up"
      end
    end
  end

  test "B14: Credit from INV-x is exactly what INV-x charged, its tax as charged; the work is billed once to the cent" do
    approved_quote([ [ "r", "Roof", 1, "10.10" ] ], tax: "10")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => "3.35"))
    assert_equal [ 34, 3_69 ], [ early.tax_cents, early.total_cents ]
    final = send!(bill_job(complete(job)))
    assert_equal [ [ early.number, 3_69 ] ], client_credits(final), "not $3.68"
    assert_equal [ 67, 7_42 ], [ final.tax_cents, final.total_cents ], "$1.01 of tax in all, less the $0.34 charged"
    assert_equal 11_11, early.total_cents + final.total_cents, "the quote's $11.11"

    approved_quote([ [ "r", "Roof", 1, "10.10" ] ], tax: %w[10 2.5])
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => "3.35"))
    final = send!(bill_job(complete(job)))
    assert_equal [ [ early.number, early.total_cents ] ], client_credits(final), "two rates, each as charged"
    assert_equal @quote.reload.total_cents, early.total_cents + final.total_cents
    assert_equal [ 1_01, 25 ], as_business(@business) { [ early, final ].map { _1.reload.totals.taxes.map { |t| t.amount.cents } }.transpose.map(&:sum) }
  end

  # Owner, 2026-11-24: no cent is kept or owed. Each progress invoice is taxed on everything billed
  # so far, less the tax already charged, so progress never rounds past the whole job's tax.
  test "B14: three progress invoices that each round up charge the whole job's tax once, and the final is never short" do
    approved_quote([ [ "r", "Roof", 1, "10.05" ] ], tax: "10")
    job = make(r: 1)
    early = 3.times.map { send!(lower(progress(job), "Roof" => "3.35")) }
    assert_equal [ 34, 33, 34 ], early.map(&:tax_cents), "$0.335 rounds up each time alone: $0.34 three times is $1.02, $0.01 over the $1.01 on $10.05"
    final = send!(bill_job(complete(job)))
    assert_equal early.map(&:total_cents), client_credits(final).map(&:last), "each Credit from is what it charged"
    assert_equal [ 0, 0 ], [ final.tax_cents, final.total_cents ], "its tax is the whole job's $1.01, less the $1.01 charged"
    assert_equal 11_06, (early + [ final ]).sum(&:total_cents), "the quote's $11.06"
    assert_equal @quote.reload.total_cents, (early + [ final ]).sum(&:total_cents)
  end

  # B16 (owner, 2026-11-24): a quote line's percent discount is shared cumulatively, so a line's bills
  # add up to the quote's discount on it, to the cent, however the work is split.
  test "B16: a percent line discount split over two jobs adds up to the quote's" do
    approved_quote([ [ "l", "Line", 6, 737 ] ], line_percents: { "l" => "33.33" })
    assert_equal [ 2948_15, 1473_85 ], as_business(@business) { [ @quote.reload.total_cents, @quote.line_items.first.reload.then { _1.line_amount_cents - BillingLedger.subtotal_cents(_1, "USD") } ] }
    jobs = [ make(l: 3), make(l: 3) ]
    jobs.each { complete(_1) }
    invoice = send!(bill_quote)
    assert_equal [ 2948_15, 1473_85 ], [ invoice.total_cents, as_business(@business) { invoice.reload.line_items.sum { _1.discount_share_cents } } ], "$736.93 + $736.92, not $736.93 twice"
  end

  test "B16: a percent line discount billed one job at a time, two tax rates, adds up to the quote's" do
    approved_quote([ [ "l", "Line", 6, "737.37" ] ], line_percents: { "l" => "33.33" }, tax: %w[6.25 2.5])
    jobs = [ make(l: 3), make(l: 3) ]
    invoices = jobs.map { send!(bill_job(complete(_1))) }
    assert_equal @quote.reload.total_cents, invoices.sum(&:total_cents), "billed = the quote's total"
    assert_equal as_business(@business) { @quote.totals.taxes.map { _1.amount.cents } }, as_business(@business) { invoices.map { _1.reload.totals.taxes.map { |t| t.amount.cents } }.transpose.map(&:sum) }, "tax too, at each rate"
  end

  # B15 (owner, 2026-11-24): the last invoice for a quote takes the rounding, so its invoices
  # charge the quote's tax to the cent, at each rate.
  test "B15: two final invoices with no progress charge the quote's tax to the cent, the last taking the rounding" do
    approved_quote([ [ "a", "Gutters", 1, "3.30" ], [ "b", "Fascia", 1, "3.30" ] ], tax: %w[6.25 2.5])
    quote_tax = as_business(@business) { @quote.reload.totals.taxes.map { _1.amount.cents } }
    assert_equal [ 41, 17 ], quote_tax, "6.25% of $6.60 is $0.4125, 2.5% is $0.165 (half up)"
    first = send!(bill_job(complete(make(a: 1))))
    second = send!(bill_job(complete(make(b: 1))))
    assert_equal [ [ 21, 8 ], [ 20, 9 ] ], [ first, second ].map { |invoice| as_business(@business) { invoice.reload.totals.taxes.map { _1.amount.cents } } }, "alone each is $0.21 and $0.08; the second takes the cent"
    assert_equal @quote.reload.total_cents, first.total_cents + second.total_cents, "billed = the quote's $#{format("%.2f", @quote.total_cents / 100.0)}"
  end

  test "B15: a final drafted before another goes out is taxed after it, and the quote's tax still comes to the cent" do
    approved_quote([ [ "a", "Gutters", 1, "3.30" ], [ "b", "Fascia", 1, "3.30" ] ], tax: %w[6.25 2.5])
    one = bill_job(complete(make(a: 1)))
    two = bill_job(complete(make(b: 1)))
    send!(two)
    send!(one)
    assert_equal @quote.reload.total_cents, total(one) + total(two)
  end

  # B17 (owner, 2026-11-24): a progress invoice credited across two finals carries all of its tax,
  # even where a final's own tax at that cumulative rounding is a cent short of its share.
  test "B17: progress credited across two finals: Credit from is exactly what it charged and billed = the quote" do
    approved_quote([ [ "e", "Eaves", 1, "460.30" ], [ "l", "Ledger", 2, "202.48" ] ], tax: "6.25")
    jobs = [ make(e: 1), make(l: 1), make(l: 1) ]
    early = send!(lower(progress(@quote), "Eaves" => nil, "Ledger" => "404.96"))
    assert_equal 25_31, early.tax_cents
    finals = jobs.map { send!(bill_job(complete(_1))) }
    rows = finals.flat_map { client_credits(_1) }
    assert_equal [ early.number ] * 2, rows.map(&:first)
    assert_equal early.total_cents, rows.sum(&:last), "all $25.31 of its tax is carried"
    assert_equal @quote.reload.total_cents, early.total_cents + finals.sum(&:total_cents), "billed = the quote's total"
    assert finals.all? { _1.total_cents >= 0 && total_tax(_1) >= 0 }
  end

  # B18: reworking a progress draft after another invoice goes out refits it to what's left, with its
  # checks on (never saved over the limit).
  test "B18: a progress draft is refitted to what's left when a void returns the quote's discount" do
    approved_quote([ [ "a", "Gutters", 1, 100 ], [ "b", "Roof", 1, 100 ] ], discount: "50")
    final = as_business(@business) { Invoice.from_job!(complete(make(a: 1)).reload, by: @owner, discount: "all") }
    send!(final)
    job = make(b: 1)
    draft = progress(job)
    held = total(draft)
    as_business(@business) { final.reload.void!(reason: "Redo", by: @owner) }
    now = total(draft)
    assert_equal [ 100_00, 75_00 ], [ held, now ], "the Roof's $100 held no discount; with $50 to come, its final charges $75"
    assert_empty as_business(@business) { draft.reload.tap(&:validate).errors.full_messages }, "and the draft is within the limit, not saved over it"
    assert_equal "Fitted to what's left: Roof lowered to what's left", as_business(@business) { ApplicationController.helpers.invoice_event_text(draft.events.find_by!(kind: "progress_refitted")) }
  end

  # Seed 55, scenario 62's shape (owner, 2026-11-24): one cumulative base for all of a quote's
  # invoices, so a final never charges less tax than the credits it carries leave room for.
  test "one cumulative base: progress, another job's final, then the progress's final: exact rows, no negative tax, the quote's tax" do
    approved_quote([ [ "e", "Eaves", 1, "460.24" ], [ "l", "Ledger", 1, "347.44" ] ], tax: "6.25")
    eaves, ledger = make(e: 1), make(l: 1)
    early = send!(lower(progress(ledger), "Ledger" => "347.44"))
    assert_equal 21_72, early.tax_cents, "6.25% of $347.44 is $21.715"
    first = send!(bill_job(complete(eaves)))
    assert_equal 28_76, first.tax_cents, "6.25% of $807.68 is $50.48, less the $21.72 charged (alone it would round up to $28.77)"
    last = send!(bill_job(complete(ledger)))
    assert_equal [ [ early.number, early.total_cents ] ], client_credits(last), "Credit from is what it charged"
    assert_equal [ 0, 0 ], [ last.tax_cents, last.total_cents ]
    assert_equal 21_72, as_business(@business) { last.reload.totals(credits: false).tax_total.cents }, "the client sees its tax with the credit's, then the credit"
    assert_equal @quote.reload.total_cents, [ early, first, last ].sum(&:total_cents), "billed = the quote's $858.16"
  end

  # B19: a void takes an invoice out of the base after a later one rounded up on it. No invoice's
  # tax goes below zero; what was charged past the true tax is owed to the client.
  test "B19: after a void, the final's tax stops at zero and the cent charged past the true tax is owed" do
    approved_quote([ [ "a", "A", 1, "1.04" ], [ "b", "B", 1, "1.04" ] ], tax: "10")
    ja, jb = make(a: 1), make(b: 1)
    first = send!(progress(ja))
    second = send!(progress(jb))
    assert_equal [ 1_14, 1_15 ], [ first, second ].map(&:total_cents), "10% of $2.08 is $0.21, less the $0.10 charged"
    as_business(@business) { first.reload.void!(reason: "Redo", by: @owner) }
    final = send!(bill_job(complete(jb)))
    assert_equal [ 0, 0 ], [ final.tax_cents, final.total_cents ], "never below zero"
    assert_equal [ [ second.number, 1_15 ] ], client_credits(final), "Credit from stays exact"
    as_business(@business) do
      ledger = BillingLedger.new(quote: @quote.reload)
      assert_equal 1, ledger.tax_over_charged_cents, "$0.11 charged against $0.10 on $1.04"
      assert_equal [ 1, 0 ], ledger.summary.values_at(:over_billed, :owed), "over-billed while A's work is still to bill"
    end
    last = send!(bill_job(complete(ja)))
    assert_equal 10, last.tax_cents, "A's final takes the cent back: $0.21 on $2.08 in all"
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).tax_over_charged_cents }
    assert_equal @quote.reload.total_cents, [ second, final, last ].sum(&:total_cents)
  end

  # B20: the quote's discount stays in its taxed/untaxed mix while that group's work is on another
  # draft, which works its share out again when this one goes out.
  test "B20: with progress credited on a draft final, a taxed final doesn't take the untaxed work's share" do
    approved_quote([ [ "x", "Roof", 1, 300 ], [ "y", "Gutters", 1, 100 ], [ "u", "Haul away", 1, 50 ] ], tax: "10", discount: "45", untaxed: [ "u" ])
    jx, jy, ju = make(x: 1), make(y: 1), make(u: 1)
    early = send!(lower(progress(jx), "Roof" => 270))
    held = bill_job(complete(jx)) # a draft: it credits the progress when it goes out
    complete(ju) # done, not billed yet
    first = send!(bill_job(complete(jy)))
    from = as_business(@business) { first.reload.quote_discount_parts.flat_map { _1["from"] }.uniq }
    assert_equal [ { "name" => "State", "percent" => "10.0" } ], from, "only the taxed group's share: the untaxed work takes its own"
    rest = [ send!(bill_job(ju)), send!(held) ]
    invoices = [ early, first, *rest ]
    assert_equal @quote.reload.total_cents, invoices.sum(&:total_cents), "billed = the quote's total"
    assert_equal as_business(@business) { @quote.totals.tax_total.cents }, invoices.sum(&:tax_cents)
  end

  test "B18: a progress draft whose line has nothing left loses that line, keeps the rest, and says why" do
    approved_quote([ [ "x", "Roof", 1, 100 ], [ "y", "Gutters", 1, 100 ] ])
    jx = make(x: 1)
    make(y: 1)
    draft = progress(@quote)
    assert_equal %w[Roof Gutters], as_business(@business) { draft.reload.current_line_items.map(&:name) }
    send!(bill_job(complete(jx)))
    as_business(@business) do
      draft.reload
      assert_equal [ %w[Gutters], 100_00 ], [ draft.current_line_items.map(&:name), draft.total_cents ], "the Roof is on its final now"
      assert_empty draft.tap(&:validate).errors.full_messages
      event = draft.events.find_by!(kind: "progress_refitted")
      assert_equal "Fitted to what's left: Roof taken off, nothing left to bill", ApplicationController.helpers.invoice_event_text(event)
    end
  end

  # W04: over-billed taxed progress can only come off lines at its rates, so the most of the quote's
  # discount a final may take never cuts it (room on an untaxed line doesn't count for it).
  test "W04: the most of the quote's discount a final can take never cuts an over-billed credit" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ], [ "g", "Gutters", 1, 300 ], [ "h", "Haul away", 1, 300 ], [ "k", "Fence", 1, 500 ] ], tax: "10", discount: "400", untaxed: [ "h" ])
    make(k: 1) # still to do: this final isn't the last
    send!(lower(progress(@quote), "Tree removal" => 800, "Gutters" => nil, "Haul away" => nil, "Fence" => nil))
    send!(bill_job(complete(make(t: 10), "Tree removal" => 6))) # 4 not done: progress is over-billed
    final = bill_job(complete(make(g: 1, h: 1)))
    over = -> { as_business(@business) { final.reload.credits.select { _1.kind == "over_billed" }.sum(&:amount_cents) } }
    at_min = over.call
    assert_operator at_min, :>, 0
    range = as_business(@business) { final.reload.quote_discount_range }
    as_business(@business) { final.reload.update!(quote_discount_applied: format("%.2f", range[:max] / 100.0)) }
    assert_equal at_min, over.call, "the maximum (#{range[:max]}) keeps the over-billed credit whole"
  end

  # U03: tax-inclusive prices: a credit takes off the tax inside it as its progress invoice charged
  # it, so "Credit from" is exactly what that invoice charged.
  test "U03: with prices including tax, a credit carries the tax inside it as charged" do
    approved_quote([ [ "r", "Roof", 1, "10.10" ] ], tax: "10", inclusive: true)
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => "3.35"))
    final = send!(bill_job(complete(job)))
    assert_equal [ [ early.number, 3_35 ] ], client_credits(final)
    assert_equal [ 10_10, 6_75 ], [ early.total_cents + final.total_cents, final.total_cents ]
    taxes = as_business(@business) { [ early, final ].map { _1.reload.totals.taxes.sum { |t| t.amount.cents } } }
    assert_equal as_business(@business) { @quote.reload.totals.tax_total.cents }, taxes.sum, "the tax inside $10.10, once: #{taxes}"
  end

  # B21: a $0.00 progress invoice is never sent; a line on its final comes off even at $0.
  test "B21: a progress draft refit to $0 after its job's final goes out is refused at send" do
    approved_quote([ [ "a", "Roof", 1, 100 ], [ "b", "Gutters", 1, 50 ] ], tax: "10")
    job = make(a: 1, b: 1)
    draft = lower(progress(job), "Roof" => 0, "Gutters" => 20)
    send!(bill_job(complete(job)))
    as_business(@business) { assert_equal 0, draft.reload.total_cents }
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(draft) }
    assert_match "nothing is left to bill as progress", error.message
    assert_equal "draft", draft.reload.status

    approved_quote([ [ "r", "Roof", 1, 100 ] ])
    zero = lower(progress(make(r: 1)), "Roof" => 0)
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(zero) }
    assert_match "is left to bill as progress", error.message, "a $0.00 progress invoice isn't sent, with work left or not"
  end

  # X02: a draft final holding a share of the quote's discount: that share isn't room for more, so
  # the invoice going out first takes what the draft's work can't.
  test "B20: a draft final's held share isn't counted again as room for the discount" do
    approved_quote([ [ "a", "Roof", 1, 40 ], [ "b", "Gutters", 1, 100 ] ], discount: "60")
    held = bill_job(complete(make(a: 1)))
    as_business(@business) { held.reload.update!(quote_discount_applied: "30") }
    first = bill_job(complete(make(b: 1)))
    assert_equal 20_00, as_business(@business) { first.reload.quote_discount_range[:min] }, "$30 left; the Roof's draft can take only $10 more"
    send!(first)
    held = send!(held)
    assert_equal @quote.reload.total_cents, first.total_cents + held.total_cents, "billed = the quote's $80.00"
  end

  # B22: a group with no work left (done short) can't block another group's progress: what it was
  # already short is the work's, not the progress invoice's.
  test "B22: progress on untaxed work isn't refused because the taxed work was done short" do
    approved_quote([ [ "a", "Shingles", 2, 679 ], [ "b", "Haul away", 10, "33.33" ] ], tax: "10", percent: "15", untaxed: [ "b" ])
    taxed, untaxed = make(a: 2), make(b: 10)
    send!(bill_job(complete(taxed, "Shingles" => 0)))
    early = progress(untaxed)
    as_business(@business) do
      assert_empty early.reload.tap(&:validate).errors.full_messages
      assert_operator early.total_cents, :<=, 333_30 - 50_00, "no more than the final will charge, the untaxed $50.00 of the discount to come"
    end
  end

  # R03 (owner, 2026-11-23/24): with a staff discount on the last final, nothing is owed: it's
  # refused until staff lower theirs.
  test "R03: a shortfall's last final with a staff discount owes nothing and is refused until it's lowered" do
    approved_quote([ [ "a", "Deck", 1, 1000 ], [ "s", "Stump grinding", 3, 100 ] ], discount: "130")
    send!(bill_job(complete(make(a: 1))))
    last = bill_job(complete(make(s: 3), "Stump grinding" => 1))
    as_business(@business) { last.reload.tap { _1.set_discount("percent", "90") }.save! }
    range = as_business(@business) { last.reload.quote_discount_range }
    assert_equal [ 0, true ], range.values_at(:owed, :short), "$110 left, $10 fits: not owed, refused"
    assert_raises(ActiveRecord::RecordInvalid) { send!(last) }
    assert_empty as_business(@business) { last.reload.quote_discount_parts.select { _1["owed"] } }
  end

  # R04: a charge-back is taxed at the rates its discount came off, not the last invoice's.
  test "R04: the charge-back is taxed at the rates the discount came off (a re-taxed job's 8%)" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ], tax: "10", discount: "100")
    early = make(t: 5)
    retax(early, "8")
    first = send!(as_business(@business) { Invoice.from_job!(complete(early).reload, by: @owner, discount: "all") })
    assert_equal [ 100_00, 32_00 ], [ first.quote_discount_share_cents, first.tax_cents ], "8% of $400"
    last = send!(bill_job(complete(make(t: 5), "Tree removal" => 1)))
    assert_equal [ 40_00, 13_20, 153_20 ], [ as_business(@business) { last.quote_discount_charge_back.cents }, last.tax_cents, last.total_cents ],
                 "$40 back at 8% ($3.20) with $100 at 10%"
  end

  # Y04 (owner, 2026-11-24): what a group can't fit on an earlier invoice carries; it's owed only
  # on the last invoice, once the shortfall is final (here the last charges the extra back
  # instead; "shortfall to nothing" has one owed on the last).
  test "Y04: a group's part that doesn't fit on an earlier invoice carries, and is owed only on the last" do
    approved_quote([ [ "d", "Deck", 1, 100 ], [ "f", "Fence", 1, 900 ], [ "h", "Haul away", 1, 100 ] ], tax: "10", discount: "300", untaxed: [ "h" ])
    deck, fence, haul = make(d: 1), make(f: 1), make(h: 1)
    complete(fence, "Fence" => 0) # done short: no taxed work left after the deck
    first = send!(bill_job(complete(deck)))
    as_business(@business) do
      assert_empty first.reload.quote_discount_parts.select { _1["owed"] }, "the haul is still to bill: nothing is owed yet"
      assert_operator BillingLedger.new(quote: @quote.reload).outstanding_cents, :>, 0, "it carries"
    end
    last = send!(bill_job(complete(haul, "Haul away" => 0)))
    as_business(@business) do
      ledger = BillingLedger.new(quote: @quote.reload)
      parts = [ first, last ].flat_map { _1.reload.quote_discount_parts }
      applied = parts.reject { _1["owed"] }.sum { _1["cents"].to_i }
      owed = parts.select { _1["owed"] }.sum { _1["cents"].to_i }
      assert_equal ledger.quote_discount_cents, applied + owed, "the scaled discount, given or owed, once"
    end
  end

  test "B14: a progress draft is taxed on what went out before it, whichever draft goes out first" do
    approved_quote([ [ "r", "Roof", 1, "10.05" ] ], tax: "10")
    job = make(r: 1)
    first = lower(progress(job), "Roof" => "3.35")
    second = lower(progress(job), "Roof" => "3.35")
    assert_equal [ 34, 34 ], [ first, second ].map { total_tax(_1) }, "each alone"
    send!(second)
    assert_equal [ 34, 33 ], [ second, first ].map { total_tax(_1) }, "the draft is taxed after the one that went out"
    send!(first)
    assert_equal [ 34, 33 ], [ second, first ].map { total_tax(_1) }, "and stays so once sent"
  end

  test "B14: a progress invoice credited in parts on two finals: its tax split so the parts add up to what it charged" do
    approved_quote([ [ "r", "Roof", 2, "5.05" ] ], tax: "10")
    early = send!(lower(progress(@quote), "Roof" => "7.00"))
    finals = [ make(r: 1), make(r: 1) ].map { send!(bill_job(complete(_1))) }
    rows = finals.flat_map { client_credits(_1) }
    assert_equal [ early.number ] * 2, rows.map(&:first)
    assert_equal early.total_cents, rows.sum(&:last), "the parts carry all $0.70 of its tax"
    assert_equal as_business(@business) { finals.sum { _1.totals(credits: false).total.cents } }, early.total_cents + finals.sum(&:total_cents),
                 "the finals' own totals to the cent: the progress is billed once (each final rounds its own tax)"
  end

  test "Apply now takes plain dollars only, and says when it's held to the range" do
    approved_quote([ [ "a", "A", 1, 100 ], [ "b", "B", 1, 100 ] ], discount: "50")
    draft = bill_job(complete(make(a: 1)))
    as_business(@business) do
      { "40,00" => nil, "4,0000" => nil, "1e3" => nil, "12.345" => nil, "4,000" => 4000_00, "$1,250.5" => 1250_50, "25" => 25_00 }.each do |typed, cents|
        invoice = Invoice.find(draft.id).tap { _1.quote_discount_applied = typed }
        assert_equal cents.nil?, invoice.invalid?, typed
        assert_equal cents, invoice.quote_discount_chosen_cents, typed if cents
      end
      draft.reload.tap { _1.quote_discount_applied = "4,000" }.save!
      range = draft.reload.quote_discount_range
      assert_equal [ 50_00, :max ], [ range[:applied], draft.quote_discount_held(range) ]
    end
  end

  test "a staff discount on a draft is kept apart from the quote's discount; a percent quote discount comes off as an amount" do
    approved_quote([ [ "a", "A", 1, 100 ], [ "b", "B", 1, 100 ] ], discount: "50")
    first = as_business(@business) { Invoice.from_job!(complete(make(a: 1)).reload, by: @owner, discount: "25") }
    as_business(@business) { first.reload.tap { _1.set_discount("amount", "10") }.save! }
    send!(first)
    assert_equal [ 25_00, 35_00 ], [ first.quote_discount_share_cents, first.discount_total_cents ]
    second = send!(bill_job(complete(make(b: 1))))
    assert_equal 25_00, second.quote_discount_share_cents, "the staff edit doesn't change what's left"

    approved_quote([ [ "r", "Roof", 1, 1000 ] ], percent: "10")
    job = make(r: 1)
    early = send!(progress(job))
    final = bill_job(complete(job))
    assert_equal [ 900_00, 0, 100_00 ], [ early.total_cents, final.total_cents, final.quote_discount_share_cents ], "$900 in all"
  end

  test "a void: drafts work out credits again; progress credited on an invoice that went out can't be voided first" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = bill_job(complete(job))
    assert_equal 500_00, final.total_cents
    as_business(@business) { early.reload.void!(reason: "Wrong amount", by: @owner) }
    assert_empty credits(final), "the draft worked its credits out again"
    assert_equal 1000_00, final.reload.total_cents

    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    error = assert_raises(ArgumentError) { as_business(@business) { early.reload.void!(reason: "Oops", by: @owner) } }
    assert_equal "Invoice #{early.number} is credited on #{final.number}. Void it first.", error.message
  end

  test "progress can't pass what's left of a line; a completed job and a recurring quote get none" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ])
    job = make(r: 1)
    send!(lower(progress(job), "Roof" => 600))
    second = progress(job)
    assert_equal 400_00, second.reload.subtotal_cents, "what's left of the line"
    error = assert_raises(ActiveRecord::RecordInvalid) { lower(second, "Roof" => 500) }
    assert_match "Roof: only $400.00 is left to bill.", error.message
    assert_match "is left to bill as progress", assert_raises(WorkBilling::Refused) { send!(lower(second, "Roof" => 400)) && progress(job) }.message
    assert_match "Progress billing is for work not done yet", assert_raises(WorkBilling::Refused) { progress(complete(job)) }.message
  end

  test "a discarded revision puts back the shares and credits it was sent with" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = make(r: 1)
    early = send!(lower(progress(job), "Roof" => 500))
    final = send!(bill_job(complete(job)))
    sent_with = [ final.quote_discount_share_cents, credits(final), final.total_cents ]
    assert_equal [ 100_00, [ [ "progress", early.number, 500_00 ] ], 400_00 ], sent_with
    as_business(@business) do
      final.reload.revise!(by: @owner)
      final.reload.tap { _1.set_discount("amount", "50") }.save!
      final.reload.discard_revision!(by: @owner)
    end
    assert_equal sent_with, [ final.reload.quote_discount_share_cents, credits(final), final.total_cents ]
  end

  test "the quote's over-billed figure is what the client was charged, with tax (owner, 2026-11-23)" do
    approved_quote([ [ "t", "Tree removal", 10, 100 ] ], tax: "10")
    send!(lower(progress(@quote), "Tree removal" => 800))
    send!(bill_job(complete(make(t: 10), "Tree removal" => 6)))
    summary = as_business(@business) { BillingLedger.new(quote: @quote.reload).summary }
    assert_equal({ billed: 880_00, credited: 660_00, over_billed: 0, owed: 220_00 }, summary, "nothing is left to bill: owed to the client")
  end
end

# Two drafts that would both credit the same over-billing, sent at once: the quote's lock queues
# the second, which works its credits out again and finds it used.
class ProgressBillingRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two drafts sent at once credit over-billing once" do
    business = businesses(:one)
    owner = users(:one)
    quote = as_business(business) do
      client = Client.create!(display_name: "Race", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap do
        _1.sync_line_items([ [ "t", 10, "100" ], [ "g", 1, "300" ], [ "s", 1, "300" ] ].map { |key, quantity, price| { "key" => key, "name" => key, "quantity" => quantity.to_s, "unit_price" => price } })
        _1.save!
        _1.update_columns(status: "approved")
      end
    end
    drafts = as_business(business) do
      lines = quote.line_items.index_by(&:key)
      early = WorkBilling.bill_progress!(quote, by: owner)
      early.line_items.each { _1.key == early.line_items.first.key ? _1.assign_attributes(unit_price: "80") : _1.mark_for_destruction }
      early.save!
      early.mark_sent!(by: owner, channel: "link")
      trees = Job.from_quote!(quote.reload, by: owner, picks: { lines["t"].id => "10" })
      trees.complete!(by: owner, done: { trees.line_items.sole.id => "6" })
      Invoice.from_job!(trees.reload, by: owner).mark_sent!(by: owner, channel: "link")
      %w[g s].map do |key|
        job = Job.from_quote!(quote.reload, by: owner, picks: { lines[key].id => "1" })
        job.complete!(by: owner)
        Invoice.from_job!(job.reload, by: owner)
      end
    end
    assert_equal [ 200_00, 200_00 ], as_business(business) { drafts.map { _1.reload.credits.sum(:amount_cents) } }, "both drafts show it"

    drafts.map do |draft|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { as_business(business) { Invoice.find(draft.id).mark_sent!(by: owner, channel: "link") } }
      end
    end.each(&:join)
    assert_equal 200_00, as_business(business) { InvoiceCredit.counted.where(invoice_id: drafts.map(&:id)).sum(:amount_cents) }
  ensure
    if quote
      as_business(business) do
        client_id = quote.client_id
        invoices = Invoice.where(client_id:)
        InvoiceCredit.where(invoice_id: invoices.select(:id)).delete_all
        invoices.order(id: :desc).each { _1.update_columns(status: "draft") && _1.destroy! }
        jobs = Job.where(client_id:)
        JobClaim.where(job_id: jobs.select(:id)).delete_all
        Visit.where(job_id: jobs.select(:id)).delete_all
        jobs.delete_all
        QuoteLineItem.where(quote_id: quote.id).delete_all
        Quote.where(client_id:).delete_all
        Client.find(client_id).destroy!
      end
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end
