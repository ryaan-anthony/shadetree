require "test_helper"

class FormattingHelperTest < ActionView::TestCase
  # Phone formats follow the business's country (#289); the fixture business is in the US.
  def current_business = @current_business ||= businesses(:one)

  test "money formats or stays blank" do
    assert_equal "$12.50", money(Money.new(1250, "USD"))
    assert_equal "No charge", money(Money.zero("USD"), zero: "No charge")
    assert_nil money(nil)
  end

  test "local_time shows the zone's wall clock and keeps the UTC instant" do
    instant = Time.utc(2026, 3, 9, 13)
    html = Time.use_zone("America/New_York") { local_time(instant) }
    assert_dom_equal '<time datetime="2026-03-09T13:00:00Z">Mar 9, 2026, 9:00 AM</time>', html
    assert_includes local_time(instant, format: :time, zone: "America/Los_Angeles"), "6:00 AM"
    assert_nil local_time(nil)
  end

  test "PLT-18: a relative time keeps its exact time on hover and for screen readers" do
    travel_to Time.utc(2026, 3, 12, 13) do
      html = Time.use_zone("America/New_York") { local_time_ago(Time.utc(2026, 3, 9, 13)) }
      assert_dom_equal '<time datetime="2026-03-09T13:00:00Z" title="Mar 9, 2026, 9:00 AM">3 days ago<span class="sr-only">, Mar 9, 2026, 9:00 AM</span></time>', html
    end
  end

  test "PLT-18: outside feeds, the absolute date with how long ago on hover" do
    travel_to Time.utc(2026, 3, 12, 13) do
      html = Time.use_zone("America/New_York") { local_date_ago(Time.utc(2026, 3, 9, 13)) }
      assert_dom_equal '<time datetime="2026-03-09T13:00:00Z" title="3 days ago">Mar 9, 2026</time>', html
      assert_includes Time.use_zone("America/New_York") { local_date_ago(Time.utc(2026, 3, 9, 13), time_of_day: true) }, "Mar 9, 2026, 9:00 AM"
    end
  end

  test "PLT-18: a line's quantity and price, and contact methods in their format" do
    line = Struct.new(:quantity_label, :unit_price)
    assert_equal "2 visits × $45.00", line_quantity(line.new("2 visits", Money.new(4500, "USD")))
    assert_equal "2 visits", line_quantity(line.new("2 visits", nil))
    as_business(current_business) do
      assert_equal "(555) 380-3141", contact_value(ClientContactMethod.new(kind: "phone", value: "555.380.3141"))
      assert_equal "a@example.com", contact_value(ClientContactMethod.new(kind: "email", value: "a@example.com"))
    end
    assert_nil contact_value(nil)
  end

  test "local_date never shifts" do
    html = Time.use_zone("Pacific/Kiritimati") { local_date(Date.new(2026, 12, 1)) }
    assert_dom_equal '<time datetime="2026-12-01">Dec 1, 2026</time>', html
  end

  test "phone numbers: North American ones formatted and dialled with +1, others as typed (QA #274)" do
    assert_equal "(215) 555-1212", phone_number("2155551212")
    assert_equal "(215) 555-1212", phone_number("+1 215.555.1212")
    assert_equal "tel:+12155551212", phone_href("1 (215) 555-1212")
    assert_equal "+44 20 7946 0958", phone_number("+44 20 7946 0958")
    assert_equal "tel:+442079460958", phone_href("+44 20 7946 0958")
    assert_equal "215-555-1212 x12", phone_number("215-555-1212 x12")
    assert_equal "tel:+12155551212", phone_href("215-555-1212 x12"), "the extension isn't dialled"
    assert_dom_equal '<a class="x" href="tel:+12155551212">(215) 555-1212</a>', phone_link("2155551212", class: "x")
    assert_nil phone_link("")
    assert_nil phone_number(nil)
  end

  test "tel: links leave off extensions, dial vanity letters, and skip text with nothing to dial" do
    { "215.555.1212 #2" => "tel:+12155551212", "215-555-1212, 3" => "tel:+12155551212", "215-555-1212;ext=4" => "tel:+12155551212",
      "215-555-1212 ext. 12" => "tel:+12155551212", "215 555 1212 extension 7" => "tel:+12155551212",
      "1-800-GOT-JUNK" => "tel:+18004685865", "1-800-GOT-JUNK x5" => "tel:+18004685865", "1-800-FIX-XBOX" => "tel:+18003499269",
      "+44 20 7946 0958" => "tel:+442079460958", "020 7946 0958" => "tel:02079460958",
      "Office: 215 555 1212" => "tel:+12155551212" }.each do |typed, href|
      assert_equal href, phone_href(typed), typed
    end
    assert_equal "1-800-GOT-JUNK", phone_number("1-800-GOT-JUNK"), "vanity numbers are shown as typed"
    assert_equal "215.555.1212 #2", phone_number("215.555.1212 #2")
    [ "call us", "12345", "ask Bob", "Fax 555 111 2222 / cell 555 333 4444" ].each do |typed|
      assert_nil phone_href(typed), typed
      assert_equal typed, phone_link(typed), "#{typed}: plain text, no link"
    end
    assert_equal "Call", phone_link("call us") { "Call" }
  end

  test "dates leave off this year's year where asked, never on today's pages, and keep it otherwise (PLT-05)" do
    travel_to Time.zone.local(2026, 11, 20, 12) do
      assert_dom_equal '<time datetime="2026-11-20">Friday, November 20</time>', friendly_date(Date.new(2026, 11, 20))
      assert_dom_equal '<time datetime="2027-01-04">Mon, Jan 4, 2027</time>', friendly_date(Date.new(2027, 1, 4), format: :weekday)
      assert_includes friendly_date(Date.new(2027, 1, 4), year: false), ">Monday, January 4<"
      assert_includes friendly_date(Date.new(2026, 11, 20), year: true), "November 20, 2026"
      assert_includes local_date(Date.new(2026, 12, 1)), "Dec 1, 2026", "records keep the year by default"
      assert_includes local_date(Date.new(2026, 12, 1), year: :auto), ">Dec 1<"
      assert_includes local_time(Time.utc(2026, 3, 9, 13), zone: "America/New_York", year: :auto), ">Mar 9, 9:00 AM<"
      assert_includes local_time(Time.utc(2025, 3, 9, 13), zone: "America/New_York", year: :auto), "Mar 9, 2025"
    end
  end

  test "zones are named as Settings names them" do
    assert_equal "Eastern Time (US & Canada)", time_zone_label("America/New_York")
    assert_equal "Pacific Time (US & Canada)", time_zone_label(ActiveSupport::TimeZone["America/Los_Angeles"])
  end

  test "long file names are shortened in the middle, keeping the end and extension (#289)" do
    long = Data.define(:filename).new(ActiveStorage::Filename.new("close-up-upside-down-dead-cricket-brown-wood-plank-shot-degree-angle-284754777.webp"))
    assert_equal "close-up-upside-down-…284754777.webp", attachment_name(long)
    assert_equal 36, attachment_name(long).length
    short = Data.define(:filename).new(ActiveStorage::Filename.new("yard.png"))
    assert_equal "yard.png", attachment_name(short)
  end

  test "phone numbers outside North America are shown and dialled as typed (#289)" do
    { "0412 345 678" => "tel:0412345678", "06 12 34 56 78" => "tel:0612345678", "020 123 4567" => "tel:0201234567" }.each do |typed, href|
      assert_equal typed, phone_number(typed), "a US business, but not a North American number"
      assert_equal href, phone_href(typed)
    end
    assert_equal "555-010-0100", phone_number("555-010-0100"), "a 555-01xx exchange isn't a real one"
    @current_business = businesses(:one).tap { _1.country = "AU" }
    assert_equal "2155551212", phone_number("2155551212"), "an Australian business's ten digits aren't North American"
    assert_equal "tel:2155551212", phone_href("2155551212")
    assert_equal "(215) 555-1212", phone_number("+1 215 555 1212"), "+1 is North American anywhere"
    assert_equal "215-555-1212 x12", phone_number("215-555-1212 x12")
    assert_nil phone_number("  ")
  end

  test "very long file names, and names with a dot in them, are shortened without failing (#289)" do
    file = ->(name) { Data.define(:filename).new(ActiveStorage::Filename.new(name)) }
    name = attachment_name(file.("Estimate.Nov 20 2026 final copy for the Smith family"))
    assert_equal 36, name.grapheme_clusters.length
    assert name.start_with?("Estimate.Nov"), name
    assert name.end_with?("th family"), name
    emoji = attachment_name(file.(("👍🏽" * 40) + ".jpg"))
    assert_equal 36, emoji.grapheme_clusters.length
    assert emoji.end_with?(".jpg")
  end
end
