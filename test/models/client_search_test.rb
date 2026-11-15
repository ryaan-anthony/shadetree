require "test_helper"

# CLI-02: client search, filters and sorting.
class ClientSearchTest < ActiveSupport::TestCase
  setup { @business = businesses(:one) }

  def client(name, phone: "555-010-0100", email: nil, company: nil, tags: [], address: nil, business: @business)
    contacts = [ { kind: "phone", value: phone } ]
    contacts << { kind: "email", value: email } if email
    as_business(business) do
      Client.create!(display_name: name, company_name: company, tags:, contact_methods_attributes: contacts,
                     properties_attributes: (address ? [ { address_line1: address, city: "Austin", region: "TX", postal_code: "78701" } ] : []))
    end
  end

  def search(query) = as_business(@business) { Client.search(query).alphabetical.map(&:display_name) }

  test "matches partial name, company, email, phone and address" do
    client("Maria Lopez", phone: "(555) 010-0100", email: "maria@lopez.example", company: "Lopez Rentals", address: "12 Elm Street")
    client("Sam Okafor", phone: "555.010.0299", address: "9 Oak Ave")

    assert_equal [ "Maria Lopez" ], search("mar")
    assert_equal [ "Maria Lopez" ], search("RENTALS")
    assert_equal [ "Maria Lopez" ], search("lopez.example")
    assert_equal [ "Maria Lopez" ], search("elm st")
    assert_equal [ "Sam Okafor" ], search("78701 oak")
    assert_equal [ "Maria Lopez", "Sam Okafor" ], search("austin")
  end

  test "phone search ignores formatting" do
    client("Maria Lopez", phone: "(555) 010-0100")
    client("Sam Okafor", phone: "+1 555 010 0299")
    assert_equal [ "Maria Lopez" ], search("5550100100")
    assert_equal [ "Maria Lopez" ], search("010-0100")
    assert_equal [ "Sam Okafor" ], search("(555) 010.02")
    assert_equal [ "Maria Lopez", "Sam Okafor" ], search("555-010")
  end

  test "every word must match, and wildcards are literal" do
    client("Maria Lopez")
    client("Maria Chen")
    client("100% Clean Co")
    assert_equal [ "Maria Chen" ], search("maria chen")
    assert_equal [ "100% Clean Co" ], search("100%")
    assert_empty search("_aria")
    assert_equal 3, search("").size
  end

  test "search text follows edits to contacts and properties" do
    maria = client("Maria Lopez", phone: "555-010-0100", address: "12 Elm Street")
    as_business(@business) do
      maria.contact_methods.first.update!(value: "555-010-7777")
      maria.properties.first.update!(address_line1: "40 Birch Road")
      maria.update!(display_name: "Maria L. Lopez")
    end
    assert_equal [ "Maria L. Lopez" ], search("7777 birch")
    assert_empty search("elm")
    assert_empty search("0100")
  end

  test "tag filter and tag options" do
    client("A", tags: %w[commercial weekly])
    client("B", tags: %w[weekly])
    client("C")
    as_business(@business) do
      assert_equal %w[A], Client.tagged("Commercial").map(&:display_name)
      assert_equal %w[A B], Client.tagged("weekly").alphabetical.map(&:display_name)
      assert_equal %w[commercial weekly], Client.tag_options
    end
    as_business(businesses(:two)) { assert_empty Client.tag_options }
  end

  test "sorts by name, recently added and recent activity" do
    travel_to(3.days.ago) { client("Bea") }
    travel_to(2.days.ago) { client("ann") }
    carl = travel_to(1.day.ago) { client("Carl") }
    as_business(@business) do
      assert_equal %w[ann Bea Carl], Client.sorted("name").map(&:display_name)
      assert_equal %w[Carl ann Bea], Client.sorted("recent").map(&:display_name)
      Client.find_by!(display_name: "Bea").touch_activity!
      assert_equal %w[Bea Carl ann], Client.sorted("activity").map(&:display_name)
      carl.update!(notes: "Called")
      assert_equal "Carl", Client.sorted("activity").first.display_name
    end
  end

  test "search stays within the current business" do
    client("Maria Lopez")
    client("Maria Other", business: businesses(:two))
    assert_equal [ "Maria Lopez" ], search("maria")
  end
end
