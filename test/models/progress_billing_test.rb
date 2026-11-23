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
  def approved_quote(lines, tax: nil, discount: nil, line_discounts: {})
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ], properties_attributes: [ { address_line1: "4 Oak Rd", billing: true } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.tax_rate_list = tax ? [ Pricing::TaxRate.new(name: "State", percent: tax) ] : []
      quote.set_discount("amount", discount) if discount
      quote.sync_line_items(lines.map do |key, name, quantity, price|
        { "key" => key, "name" => name, "quantity" => quantity.to_s, "unit_price" => price.to_s, "taxable" => "1",
          **(line_discounts[key] ? { "discount_kind" => "amount", "discount_value" => line_discounts[key].to_s } : {}) }
      end)
      quote.save!
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
    assert_equal [ 500_00, 0, 50_00, 550_00 ], cents(final), "$1,000 less $500 billed earlier, then 10% tax"
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
    assert_equal [ 200_00, 0, 0, 200_00 ], cents(final)
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
end
