require "test_helper"

# PAY-01: invoices: numbering, terms and due dates, made from a job, a quote or from scratch,
# priced exactly like quotes, and their status rules.
class InvoiceTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York", invoice_due_days: 15, invoice_terms: "Payment due within 15 days.")
    Current.business = @business
    @owner = users(:one)
    @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                            properties_attributes: [ { address_line1: "12 Elm St", billing: true } ])
    @rate = Pricing::TaxRate.new(name: "Sales tax", percent: "8.25")
  end

  teardown { Current.reset }

  def rows(*lines) = lines.each_with_index.map { |(name, qty, price), index| { "key" => "k#{index}", "name" => name, "quantity" => qty.to_s, "unit_price" => price.to_s, "taxable" => "1" } }

  def approved_quote
    quote = Quote.start(client: @maria)
    quote.tax_rate_list = [ @rate ]
    quote.set_discount("percent", "10")
    quote.sync_line_items(rows([ "Mowing", 2, "45" ], [ "Hedge trim", 1, "80" ]))
    quote.save!
    quote.update_columns(status: "approved")
    quote
  end

  test "a new invoice: the next number, today, and the business's terms and due days" do
    invoice = Invoice.start(client: @maria, created_by: @owner)
    assert_equal [ "INV-0001", "draft", @business.today, "net_15", @business.today + 15, "Payment due within 15 days." ],
                 [ invoice.number, invoice.status, invoice.issued_on, invoice.payment_terms, invoice.due_on, invoice.terms ]
    assert_equal "INV-0002", Invoice.start(client: @maria).number
    assert_equal @maria.primary_property, invoice.property
    assert_equal [ "created" ], invoice.events.map(&:kind)

    @business.update!(invoice_due_days: 14)
    odd = Invoice.start(client: @maria)
    assert_equal [ "custom", @business.today + 14 ], [ odd.payment_terms, odd.due_on ], "14 days isn't one of the terms: a custom date"
  end

  test "terms set the due date from the issue date; a custom date is kept, but not before the issue date" do
    invoice = Invoice.start(client: @maria)
    invoice.update!(issued_on: Date.new(2026, 12, 1), payment_terms: "net_30")
    assert_equal Date.new(2026, 12, 31), invoice.due_on
    invoice.update!(payment_terms: "due_on_receipt")
    assert_equal Date.new(2026, 12, 1), invoice.due_on
    invoice.update!(payment_terms: "custom", due_on: Date.new(2027, 1, 10))
    invoice.update!(issued_on: Date.new(2026, 12, 2))
    assert_equal Date.new(2027, 1, 10), invoice.reload.due_on, "a custom date stays put"
    invoice.due_on = Date.new(2026, 11, 30)
    assert_not invoice.valid?
    assert_includes invoice.errors[:due_on], "can't be before the issue date"
  end

  test "from an approved quote: its lines, discount and taxes, so the same total; linked both ways" do
    quote = approved_quote
    invoice = Invoice.from_quote!(quote, by: @owner)
    assert_equal quote.total, invoice.total
    assert_equal [ "Mowing", "Hedge trim" ], invoice.line_items.map(&:name)
    assert_equal [ @rate ], invoice.tax_rate_list
    assert_equal [ invoice ], quote.invoices.to_a
    assert_equal({ "from" => "quote", "number" => quote.number }, invoice.events.first.data)

    quote.update_columns(status: "sent")
    assert_raises(ArgumentError) { Invoice.from_quote!(quote.reload) }
  end

  test "from a job: the job's items as they are now (with on-site changes), and the job's quote too; a job can be billed twice" do
    quote = approved_quote
    job = Job.from_quote!(quote)
    job.line_items.create!(name: "Extra mulch", quantity: 3, unit_price: "20", position: 9)
    job.save!
    first = Invoice.from_job!(job.reload, by: @owner)
    assert_equal [ "Mowing", "Hedge trim", "Extra mulch" ], first.line_items.map(&:name)
    assert_equal job.total, first.total
    assert_equal [ job, quote ], [ first.job, first.quote ]
    second = Invoice.from_job!(job)
    assert_equal [ first, second ], job.invoices.order(:id).to_a
    assert_not_equal first.number, second.number
  end

  test "lines price exactly as on a quote: the same rows, the same totals" do
    quote = Quote.start(client: @maria)
    invoice = Invoice.start(client: @maria)
    [ quote, invoice ].each do |document|
      document.tax_rate_list = [ @rate ]
      document.set_discount("amount", "5")
      document.sync_line_items(rows([ "Mowing", "2.5", "45.10" ], [ "Bags", 3, "1.99" ]))
      document.save!
    end
    assert_equal [ quote.subtotal, quote.tax_cents, quote.total ], [ invoice.subtotal, invoice.tax_cents, invoice.total ]
    assert_equal quote.totals.lines.map(&:subtotal), invoice.totals.lines.map(&:subtotal)
  end

  test "balance, outstanding and overdue (a derived indicator, not a status)" do
    invoice = Invoice.start(client: @maria)
    invoice.sync_line_items(rows([ "Mowing", 1, "100" ]))
    invoice.update!(tax_rates: [], payment_terms: "net_7")
    assert_not invoice.outstanding?
    invoice.update_columns(status: "sent", amount_paid_cents: 2500)
    assert_equal Money.new(7500, "USD"), invoice.balance
    assert_not invoice.overdue?(invoice.due_on)
    assert invoice.overdue?(invoice.due_on + 1)
    invoice.update_columns(status: "paid")
    assert_not invoice.overdue?(invoice.due_on + 1)
  end

  test "a property, job or quote must be the invoice's client's" do
    other = Client.create!(display_name: "Sam", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ],
                           properties_attributes: [ { address_line1: "9 Oak Ave" } ])
    invoice = Invoice.start(client: @maria)
    invoice.property = other.properties.first
    invoice.quote = Quote.start(client: other)
    assert_not invoice.valid?
    assert_equal [ :property, :quote ], invoice.errors.attribute_names.sort
  end

  test "at most #{BuiltDocument::MAX_LINES} lines" do
    invoice = Invoice.start(client: @maria)
    invoice.sync_line_items((0..BuiltDocument::MAX_LINES).map { { "key" => "k#{_1}", "name" => "Line #{_1}" } })
    assert_not invoice.valid?
    assert_includes invoice.errors[:base], "This invoice can have at most #{BuiltDocument::MAX_LINES} lines."
  end
end
