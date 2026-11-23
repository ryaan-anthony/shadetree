require "test_helper"

# PAY-08: progress billing, credits and discount shares, with split jobs on. The worked examples
# from #356 are rerun here, in exact cents. Every test ends reconciled (JOB-09).
class ProgressBillingTest < ActiveSupport::TestCase
  setup do
    enable_feature(:split_jobs)
    @business = businesses(:one)
    @owner = users(:one)
    as_business(@business) { @business.update!(auto_create_jobs: false) }
  end

  teardown { assert_empty as_business(@business) { JobClaim.unreconciled_lines.pluck(:id) }, "claimed = the sum of live claims" }

  # An approved quote with these lines ([key, name, quantity, price]).
  def approved_quote(lines, tax: nil, discount: nil, line_discounts: {}, untaxed: [], percent: nil, inclusive: false, quick: false)
    @quote = as_business(@business) do
      client = (@client if quick) || Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.tax_rate_list = tax ? [ Pricing::TaxRate.new(name: "State", percent: tax) ] : []
      quote.set_discount("amount", discount) if discount
      quote.set_discount("percent", percent) if percent
      quote.prices_include_tax = inclusive
      quote.sync_line_items(lines.map do |key, name, quantity, price|
        { "key" => key, "name" => name, "quantity" => quantity.to_s, "unit_price" => price.to_s, "taxable" => (untaxed.include?(key) ? "0" : "1"),
          **(line_discounts[key] ? { "discount_kind" => "amount", "discount_value" => line_discounts[key].to_s } : {}) }
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

  test "example 4: the discount base keeps billed work at its billed price after a price change" do
    approved_quote([ [ "a", "Mulch", 10, 50 ], [ "b", "Patio", 1, 500 ] ], discount: "100")
    first = send!(bill_job(complete(make(a: 10))))
    assert_equal 50_00, first.quote_discount_share_cents, "W $500 of S $1,000"
    assert_equal 450_00, first.total_cents

    # A change (QTE-10) raises the prices: mulch has nothing left to do, the patio is to do.
    as_business(@business) { line("a").update_columns(unit_price_cents: 55_00) && line("b").update_columns(unit_price_cents: 650_00) }
    second = send!(bill_job(complete(make(b: 1))))
    assert_equal 1150_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).discount_base_cents }
    assert_equal 50_00, second.quote_discount_share_cents, "target $100 of W $1,150 / S $1,150, less $50"
    assert_equal 100_00, first.quote_discount_share_cents + second.quote_discount_share_cents
  end

  test "flag off: no shares or credits" do
    disable_feature(:split_jobs)
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = as_business(@business) { Job.from_quote!(@quote, by: @owner) }
    first = send!(bill_job(job))
    second = bill_job(job)
    assert_equal [ 0, 0 ], [ first.quote_discount_share_cents, second.quote_discount_share_cents ]
    assert_empty credits(second)
  end

  test "A: progress is capped at, and defaults to, what's left after the line's expected share of the fixed discount" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], discount: "100")
    job = make(r: 1)
    early = progress(job)
    assert_equal 900_00, early.reload.subtotal_cents, "$1,000 with $100 off: at most $900 up front (owner, 2026-11-23)"
    assert_match "Roof: only $900.00 is left to bill.", assert_raises(ActiveRecord::RecordInvalid) { lower(early, "Roof" => 1000) }.message
    send!(early)
    final = bill_job(complete(job))
    assert_equal [ [ "progress", early.number, 900_00 ] ], credits(final)
    assert_equal [ 100_00, 0 ], [ final.quote_discount_share_cents, final.total_cents ]
    assert_equal 0, as_business(@business) { BillingLedger.new(quote: @quote.reload).over_billed_cents }
  end

  test "billing a quote directly takes its fixed discounts once, as shares" do
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
    send!(bill_job(complete(job)))
    error = assert_raises(ActiveRecord::RecordInvalid) { send!(draft) }
    assert_match "Roof: only $0.00 is left to bill.", error.message
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
    assert_match "must match #{@quote.number}", error.message
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
    assert_equal 110_00, as_business(@business) { BillingLedger.new(quote: @quote.reload).summary[:over_billed] }, "$100 and its tax, charged"
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

  test "S3: progress never charges a line more than the final would, after a percent discount or a lone job's fixed one" do
    approved_quote([ [ "r", "Roof", 1, 1000 ] ], percent: "10")
    early = progress(make(r: 1))
    error = assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { early.reload.tap { _1.set_discount(nil, nil) }.save! } }
    assert_match "Roof: only $900.00 is left to bill.", error.message

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

  # The reviewer's invariant (owner, 2026-11-23): across a job's progress and final invoices, the
  # client pays the work's value, within a cent per tax rate per invoice, and each "Credit from"
  # equals what that progress invoice charged.
  test "randomized: progress then final charges the work's value once, and each credit is what was charged" do
    rng = Random.new(20261123)
    credited = 0
    100.times do |n|
      tax = [ nil, "10", "6.25" ].sample(random: rng)
      discount = rng.rand(3)
      lines = Array.new(rng.rand(1..2)) { |i| [ "k#{i}", "Item #{i}", rng.rand(1..3), format("%.2f", rng.rand(20.0..400.0)) ] }
      gross = lines.sum { |_, _, quantity, price| quantity * price.to_d }
      approved_quote(lines, quick: true, tax:, inclusive: tax.present? && rng.rand < 0.2, percent: (rng.rand(5..20).to_s if discount == 1),
                            discount: (format("%.2f", gross * rng.rand(0.02..0.2)) if discount == 2))
      job = make(**lines.to_h { |key, _, quantity, _| [ key.to_sym, quantity ] })
      sent = Array.new(rng.rand(0..2)).filter_map do
        invoice = progress(job)
        amounts = as_business(@business) { invoice.reload.line_items.to_h { [ _1.name, (_1.line_amount_cents * rng.rand(0.2..1.0) / 100).round(2).to_d.to_s("F") ] } }
        lower(invoice, amounts)
        as_business(@business) { invoice.reload.tap { _1.set_discount("percent", %w[10 50].sample(random: rng)) }.save! } if rng.rand < 0.3
        send!(invoice)
      rescue WorkBilling::Refused, ActiveRecord::RecordInvalid
        nil
      end
      final = send!(bill_job(complete(job)))
      slack = (tax ? 1 : 0) * (sent.size + 1)
      work = as_business(@business) { final.reload.totals(credits: false).total.cents }
      paid = sent.sum(&:total_cents) + final.total_cents
      assert_in_delta work, paid, slack, "scenario #{n}: the work's value, once"
      shown = client_credits(final).to_h
      sent.each { assert_in_delta _1.total_cents, shown[_1.number].to_i, slack, "scenario #{n}: Credit from #{_1.number}" }
      credited += 1 if shown.any?
      @client ||= @quote.client
    end
    assert_operator credited, :>, 50, "most scenarios bill progress first"
  end
end
