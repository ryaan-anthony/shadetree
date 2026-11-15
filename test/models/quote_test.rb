require "test_helper"

# QTE-01: quotes, their lines and totals.
class QuoteTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(quote_expiry_days: 30, quote_terms: "50% due on approval.", quote_number_prefix: "Q")
  end

  def client(exempt: false, **attributes)
    as_business(@business) do
      Client.create!(display_name: "Maria Lopez", tax_exempt: exempt, contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                     properties_attributes: [ { address_line1: "12 Elm St", billing: true } ], **attributes)
    end
  end

  def row(key, name, quantity, price, taxable: true, **extra) = { "key" => key, "name" => name, "quantity" => quantity, "unit_price" => price, "taxable" => taxable ? "1" : "0", **extra }

  test "a new draft gets the next number and the business's defaults" do
    travel_to Time.utc(2026, 11, 15, 17) do
      as_business(@business) do
        TaxRate.create!(name: "State", percent: "6.25")
        maria = client
        first = Quote.start(client: maria)
        second = Quote.start(client: maria)
        assert_equal %w[Q-0001 Q-0002], [ first.number, second.number ]
        assert_equal Date.new(2026, 12, 15), first.expires_on
        assert_equal "50% due on approval.", first.terms
        assert_equal "USD", first.currency
        assert_equal maria.billing_property, first.property
        assert_equal [ Pricing::TaxRate.new(name: "State", percent: "6.25") ], first.tax_rate_list
        assert first.draft?
      end
    end
  end

  test "a tax-exempt client's draft starts without tax" do
    as_business(@business) do
      TaxRate.create!(name: "State", percent: "6.25")
      assert_empty Quote.start(client: client(exempt: true)).tax_rate_list
    end
  end

  test "totals come from the shared pricing code, with line and quote discounts and taxes per rate" do
    as_business(@business) do
      quote = Quote.start(client: client)
      quote.tax_rate_list = [ Pricing::TaxRate.new(name: "State", percent: "6.25"), Pricing::TaxRate.new(name: "County", percent: "1.5") ]
      quote.sync_line_items([
        row("a", "Mowing", "4", "45.00", discount_kind: "percent", discount_value: "10"),
        row("b", "Mulch", "2.5", "38.40"),
        row("c", "Labor", "1.5", "60", taxable: false, discount_kind: "amount", discount_value: "10")
      ])
      quote.set_discount("amount", "20")
      quote.save!

      expected = Pricing::DocumentTotals.new(
        currency: "USD", discount: Pricing::Discount.amount(Money.parse("20", "USD")),
        lines: [ Pricing::Line.new(quantity: "4", unit_price: Money.parse("45", "USD"), discount: Pricing::Discount.percent(10), tax_rates: quote.tax_rate_list),
                 Pricing::Line.new(quantity: "2.5", unit_price: Money.parse("38.40", "USD"), tax_rates: quote.tax_rate_list),
                 Pricing::Line.new(quantity: "1.5", unit_price: Money.parse("60", "USD"), discount: Pricing::Discount.amount(Money.parse("10", "USD"))) ]
      )
      totals = quote.reload.totals
      assert_equal expected.subtotal, totals.subtotal
      assert_equal expected.taxes, totals.taxes
      assert_equal expected.total, totals.total
      assert_equal [ expected.subtotal.cents, expected.total.cents, totals.tax_total.cents ], [ quote.subtotal_cents, quote.total_cents, quote.tax_cents ]
      assert_equal Money.parse("338", "USD"), totals.subtotal # 4 × 45 less 10%, 2.5 × 38.40, 1.5 × 60 less 10
    end
  end

  test "syncing lines updates by key, keeps order, removes missing lines and never duplicates" do
    as_business(@business) do
      quote = Quote.start(client: client)
      2.times do
        quote.sync_line_items([ row("a", "Mowing", "1", "45"), row("b", "Edging", "1", "15") ])
        quote.save!
      end
      assert_equal %w[Mowing Edging], quote.reload.line_items.map(&:name)

      quote.sync_line_items([ row("b", "Edging", "2", "15"), row("c", "Trim", "1", "30") ])
      quote.save!
      assert_equal [ [ "Edging", 0, BigDecimal("2") ], [ "Trim", 1, BigDecimal("1") ] ], quote.reload.line_items.map { [ _1.name, _1.position, _1.quantity ] }
      assert_equal 2, QuoteLineItem.where(quote:).count

      quote.sync_line_items([])
      quote.save!
      assert_empty quote.reload.line_items
    end
  end

  test "a line from the catalog keeps a copy, so catalog edits don't change the quote" do
    as_business(@business) do
      mow = CatalogItem.create!(name: "Weekly mow", unit_price: "45")
      quote = Quote.start(client: client)
      quote.sync_line_items([ row("a", "Weekly mow", "1", "45", "catalog_item" => mow.uid) ])
      quote.save!
      mow.update!(unit_price: "60", name: "Mow")
      line = quote.reload.line_items.first
      assert_equal [ "Weekly mow", 4500, mow ], [ line.name, line.unit_price_cents, line.catalog_item ]
    end
  end

  test "invalid input is reported without losing the rest" do
    as_business(@business) do
      quote = Quote.start(client: client)
      quote.sync_line_items([ row("a", "Mowing", "-1", "abc"), row("b", "Trim", "1", "10", discount_kind: "amount", discount_value: "50") ])
      assert_not quote.save
      first, second = quote.line_items.to_a
      assert first.errors.of_kind?(:quantity, :greater_than_or_equal_to)
      assert_includes first.errors[:unit_price], "is not a valid amount"
      assert_includes second.errors[:discount_amount], "can't be more than the line"
      assert_equal "abc", first.unit_price_before_type_cast
    end
  end

  test "the property must be the client's" do
    as_business(@business) do
      quote = Quote.start(client: client)
      other = Client.create!(display_name: "Sam", contact_methods_attributes: [ { kind: "phone", value: "5550100299" } ],
                             properties_attributes: [ { address_line1: "9 Oak Ave" } ])
      quote.property = other.properties.first
      assert_not quote.valid?
      assert_includes quote.errors[:property], "must be one of this client's properties"
    end
  end

  test "photos are re-encoded without metadata; other files are refused" do
    as_business(@business) do
      quote = Quote.start(client: client)
      tagged = Vips::Image.new_from_file(file_fixture("logo.png").to_s).mutate { _1.set_type!(GObject::GSTR_TYPE, "png-comment-0-gps", "40.7,-74.0") }
      photo = Rack::Test::UploadedFile.new(StringIO.new(tagged.write_to_buffer(".png")), "image/png", original_filename: "yard.png")
      quote.attach_files([ photo ])
      quote.save!
      stored = Vips::Image.new_from_buffer(quote.reload.attachments.first.download, "")
      assert_not_includes stored.get_fields, "png-comment-0-gps"

      quote.attach_files([ Rack::Test::UploadedFile.new(file_fixture("logo.gif"), "image/gif") ])
      assert_not quote.save
      assert_match "logo.gif must be a photo (PNG, JPEG, WebP) or a PDF", quote.errors[:base].first

      fake = Rack::Test::UploadedFile.new(StringIO.new("just some text"), "application/pdf", original_filename: "notes.pdf")
      quote.reload.attach_files([ fake ])
      assert_not quote.save, "a .pdf name doesn't make a PDF"
      real = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4\n%%EOF\n"), "application/pdf", original_filename: "plan.pdf")
      quote.reload.attach_files([ real ])
      assert quote.save
      assert_equal "application/pdf", quote.attachments.last.content_type
    end
  end

  test "quotes stay inside their business, and a client with quotes can't be deleted" do
    maria = client
    quote = as_business(@business) { Quote.start(client: maria) }
    as_business(businesses(:two)) { assert_nil Quote.find_by(id: quote.id) }
    as_business(@business) { assert_not maria.reload.deletable? }
  end

  test "client_state: drafts and answered quotes keep their status; a sent quote past its date is expired" do
    quote = as_business(@business) { Quote.start(client: client) }
    as_business(@business) do
      assert_equal :draft, quote.client_state
      assert_not quote.client_visible?
      quote.status = "sent"
      assert quote.client_visible?
      assert_equal :awaiting, quote.client_state
      quote.expires_on = @business.today
      assert_equal :awaiting, quote.client_state, "valid through its last day"
      quote.expires_on = @business.today - 1
      assert_equal :expired, quote.client_state
      quote.status = "approved"
      assert_equal :approved, quote.client_state, "an approved quote never expires"
      quote.assign_attributes(status: "sent", expires_on: nil)
      assert_equal :awaiting, quote.client_state
    end
  end
end
