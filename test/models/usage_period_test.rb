require "test_helper"

# BIL-02: usage periods (calendar months in the business's zone on Free, the billing cycle on
# a paid plan), counting once per quote, plan changes mid-period, history and tenancy.
class UsagePeriodTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one) # America/New_York
    @owner = users(:one)
  end

  def quote
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria #{SecureRandom.hex(2)}", contact_methods_attributes: [ { kind: "phone", value: "555010#{rand(1000..9999)}" } ])
      Quote.start(client:).tap do |quote|
        quote.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
        quote.save!
      end
    end
  end

  test "free plans count the calendar month in the business's time zone" do
    # 11pm Oct 31 in New York is already Nov 1 in UTC: it's October here.
    period = UsagePeriod.for(@business, at: Time.utc(2026, 11, 1, 3, 0))
    assert_equal Time.find_zone("America/New_York").local(2026, 10, 1), period.starts_at
    assert_equal Date.new(2026, 11, 1), period.resets_on
    feb = UsagePeriod.for(@business, at: Time.utc(2027, 2, 14))
    assert_equal [ Date.new(2027, 2, 1), Date.new(2027, 3, 1) ], [ feb.starts_at.to_date, feb.resets_on ]
  end

  test "paid plans count their billing cycle from the anchor, the 31st renewing at month end" do
    @business.update!(plan: plans(:starter), billing_cycle_anchor: Time.find_zone("America/New_York").local(2026, 1, 31, 10))
    feb = UsagePeriod.for(@business, at: Time.utc(2026, 2, 15))
    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28) ], [ feb.starts_at.to_date, feb.resets_on ]
    mar = UsagePeriod.for(@business, at: Time.utc(2026, 3, 30))
    assert_equal [ Date.new(2026, 2, 28), Date.new(2026, 3, 31) ], [ mar.starts_at.to_date, mar.resets_on ], "back to the 31st when the month has one"
    assert_equal Date.new(2026, 4, 30), UsagePeriod.for(@business, at: Time.utc(2026, 4, 15)).resets_on
    assert_equal [ Date.new(2026, 4, 30), Date.new(2026, 5, 31) ], UsagePeriod.for(@business, at: Time.utc(2026, 5, 2)).then { [ _1.starts_at.to_date, _1.resets_on ] }
    @business.update!(plan: plans(:free))
    assert_equal Date.new(2026, 5, 1), UsagePeriod.for(@business, at: Time.utc(2026, 4, 15)).resets_on, "back on Free: calendar months"
  end

  test "a quote counts once however often it's sent; a plan change keeps the period's usage" do
    first, second = quote, quote
    Tenancy.with_business(@business) do
      first.mark_sent!(by: @owner, channel: "link")
      first.mark_sent!(by: @owner, channel: "link")
      first.revise!(by: @owner)
      first.mark_sent!(by: @owner, channel: "link")
      second.mark_sent!(by: @owner, channel: "email", recipient: "m@example.com")
    end
    assert_equal 2, @business.entitlements.used(:quotes_sent)
    assert_equal 3, @business.entitlements.remaining(:quotes_sent)
    @business.update!(plan: plans(:starter))
    entitlements = @business.reload.entitlements
    assert_equal [ 2, 28 ], [ entitlements.used(:quotes_sent), entitlements.remaining(:quotes_sent) ], "same usage, the new limit"
  end

  test "history keeps earlier periods; another business's sends never count; counting is one query" do
    travel_to Time.utc(2026, 9, 10) do
      Tenancy.with_business(@business) { UsageEvent.record!("quote_sent", quote, at: 3.months.ago) }
      Tenancy.with_business(businesses(:two)) do
        client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550109999" } ])
        UsageEvent.record!("quote_sent", Quote.start(client:))
      end
      history = UsagePeriod.for(@business).history(count: 24)
      assert_equal 24, history.size
      assert_equal [ 0, 0, 0, 1 ], history.first(4).map(&:used)
      assert_equal Date.new(2026, 6, 1), history[3].starts_at.to_date
      queries = 0
      callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { UsagePeriod.for(@business).used }
      assert_equal 1, queries
    end
  end
end
