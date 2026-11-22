require "test_helper"

# QTE-08: which technician drafts can go to the client without the office's review, and why not.
class SendWithoutReviewTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    @owner = users(:one)
    @tech = User.create!(email: "marcus-#{SecureRandom.hex(3)}@example.com", password: "password123", first_name: "Marcus", confirmed_at: Time.current)
    @membership = BusinessUser.create!(user: @tech, business: @business, role: "technician")
    Tenancy.with_business(@business) do
      @state = TaxRate.create!(name: "State", percent: "8", applies_by_default: true)
      @gutters = CatalogItem.create!(name: "Gutter clean", unit: "visit", unit_price: "150", send_without_review: true)
      @mulch = CatalogItem.create!(name: "Mulch", unit: "custom", custom_unit: "yard", unit_price: "60", send_without_review: true, taxable: false)
      @design = CatalogItem.create!(name: "Garden design", unit: "hour", unit_price: "90")
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @request_record = ServiceRequest.create!(client: @maria, source: "phone", description: "Gutters")
      @quote = Quote.start(client: @maria, created_by: @tech)
      @quote.update!(service_request: @request_record)
    end
  end

  def with_tenant(&) = Tenancy.with_business(@business, &)

  def row(item, key: item.uid, **changes)
    { "key" => key, "catalog_item" => item.uid, "name" => item.name, "unit" => item.unit_label, "unit_price" => item.unit_price.to_s,
      "quantity" => "1", "taxable" => item.taxable ? "1" : "0" }.merge(changes.transform_keys(&:to_s))
  end

  def lines(*rows)
    with_tenant do
      @quote.sync_line_items(rows)
      @quote.save!
      @quote = Quote.includes(line_items: :catalog_item).find(@quote.id)
    end
  end

  def reasons = with_tenant { SendWithoutReview.new(Quote.includes(:business, line_items: :catalog_item).find(@quote.id)).reasons }

  test "a draft of only those services at their prices qualifies; quantity, name, description, terms and dates may change" do
    lines(row(@gutters, quantity: "3", name: "Gutter clean, front and back", description: "Both storeys"), row(@mulch, quantity: "2.5"))
    with_tenant { @quote.update!(terms: "Pay on the day", expires_on: Date.current + 3, title: "Spring work", message: "Hi Maria") }
    assert_equal [], reasons
    grounds = with_tenant { SendWithoutReview.new(@quote).grounds }
    assert_equal({ "services" => [ "Gutter clean", "Mulch" ], "total" => "$636.00", "cap" => nil }, grounds)
  end

  test "each thing the office needs to see is a reason, the first named first" do
    lines(row(@gutters, unit_price: "140"), { "key" => "c", "name" => "Haul away", "unit_price" => "20", "quantity" => "1" }, row(@design))
    assert_equal [ "Gutter clean: price changed", "Haul away: custom line", "Garden design: needs review" ], reasons

    lines(row(@gutters, unit: "hour"))
    assert_equal [ "Gutter clean: unit changed" ], reasons
    lines(row(@gutters, taxable: "0"))
    assert_equal [ "Gutter clean: price changed" ], reasons, "a taxable change counts as a price edit"
    lines(row(@gutters, unit_price: "160"))
    assert_equal [ "Gutter clean: price changed" ], reasons, "higher is a price edit too"
    lines(row(@gutters, discount_kind: "percent", discount_value: "10"))
    assert_equal [ "Gutter clean: discount" ], reasons

    lines(row(@gutters, discount_kind: ""))
    with_tenant { @quote.set_discount("amount", "5") && @quote.save! }
    assert_equal [ "Quote discount" ], reasons
  end

  test "the price list changing after the line was added, and adding it again" do
    lines(row(@gutters))
    with_tenant { @gutters.update!(unit_price: "175") }
    assert_equal [ "Gutter clean: the price list changed" ], reasons
    lines(row(@gutters, key: "again", unit_price: "175"))
    assert_equal [], reasons
  end

  test "a service switched off, archived or without a price stops it" do
    lines(row(@gutters))
    with_tenant { @gutters.update!(send_without_review: false) }
    assert_equal [ "Gutter clean: needs review" ], reasons
    with_tenant { @gutters.update!(send_without_review: true) && @gutters.archive! }
    assert_equal [ "Gutter clean: service archived" ], reasons
    with_tenant { @gutters.update!(archived_at: nil, unit_price: nil) }
    assert_equal [ "Gutter clean: priced on each quote" ], reasons
  end

  test "taxes and prices including tax are the defaults, or it's \"Tax changed\"" do
    lines(row(@gutters))
    with_tenant { @quote.update!(tax_rate_list: []) }
    assert_equal [ "Tax changed" ], reasons
    with_tenant { @quote.update!(tax_rate_list: [ @state.to_pricing ], prices_include_tax: true) }
    assert_equal [ "Tax changed" ], reasons
  end

  test "it has to be at its request's location, priced for it" do
    branch = with_tenant { Location.create!(name: "North", address_line1: "1 North Rd") }
    lines(row(@gutters))
    with_tenant { @quote.update!(location: branch) }
    assert_equal [ "Another location" ], reasons
    with_tenant { @request_record.update!(location: branch) }
    assert_equal [ "Another location" ], reasons, "moved, but still priced for the main location"
    with_tenant do
      LocationPrice.create!(location: branch, catalog_item: @gutters, unit_price_cents: 16_500)
      @quote.reprice_for_location!
    end
    @quote = with_tenant { Quote.includes(line_items: :catalog_item).find(@quote.id) }
    assert_equal [], reasons, "at the branch's price, for the branch"
  end

  test "the cap is measured after tax; a $0.00 quote qualifies" do
    lines(row(@gutters, quantity: "3")) # 450 + 8% = 486
    @business.update!(without_review_cap: "480")
    assert_equal [ "Over $480.00" ], reasons
    @business.update!(without_review_cap: "486")
    assert_equal [], reasons

    lines(row(@gutters, quantity: "0"))
    assert_equal [], reasons
  end

  test "it applies to a revision-1 draft from a request, by a member who quotes requests and doesn't send" do
    assert SendWithoutReview.applies_to?(@quote, @membership)
    assert_not SendWithoutReview.applies_to?(@quote, @business.business_users.find_by!(user: @owner)), "the office sends anyway"
    with_tenant { @quote.update_columns(revision: 2) }
    assert_not SendWithoutReview.applies_to?(@quote, @membership)
    with_tenant { @quote.update_columns(revision: 1, created_by_id: @owner.id) }
    assert_not SendWithoutReview.applies_to?(@quote, @membership), "someone else's"
    senders = with_tenant { Role.create!(name: "Senior", permissions: %w[field_work quote_requests send_own_quotes]) }
    with_tenant { @quote.update_columns(created_by_id: @tech.id) }
    @membership.update!(role: "custom", role_id: senders.id)
    assert_not SendWithoutReview.applies_to?(@quote, @membership), "they send their own anyway"
  end
end
