require "test_helper"

# CLI-01: client records, contact methods and properties.
class ClientTest < ActiveSupport::TestCase
  setup { @business = businesses(:one) }

  def phone(value, **rest) = { kind: "phone", value:, **rest }
  def email(value, **rest) = { kind: "email", value:, **rest }

  def create_client(contacts: [ phone("555-010-0100") ], properties: [], **attributes)
    as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: contacts, properties_attributes: properties, **attributes)
    end
  end

  test "needs a name and at least one contact method" do
    as_business(@business) do
      client = Client.new(display_name: " ")
      assert_not client.valid?
      assert client.errors.of_kind?(:display_name, :blank)
      assert_includes client.errors[:base], "Add an email or a phone number so you can reach this client."
      assert Client.new(display_name: "Ana", contact_methods_attributes: [ email("ana@example.com") ]).valid?
    end
  end

  test "blank new rows are ignored; emptied saved rows are removed" do
    client = create_client(contacts: [ phone("555-010-0100"), email("") ], properties: [ { address_line1: "", city: "" } ])
    assert_equal 1, as_business(@business) { client.contact_methods.count }
    assert_empty client.properties.to_a

    as_business(@business) do
      client.update!(contact_methods_attributes: [ { id: client.contact_methods.first.id, value: "" }, email("m@example.com") ])
      assert_equal [ "m@example.com" ], client.reload.contact_methods.map(&:value)
      assert_not client.update(contact_methods_attributes: [ { id: client.contact_methods.first.id, value: "" } ])
    end
  end

  test "contact methods are validated and normalized for matching" do
    client = create_client(contacts: [ phone("+1 (555) 010-0100"), email(" Maria@Example.COM ") ])
    assert_equal %w[5550100100 maria@example.com], client.contact_methods.map(&:normalized)
    assert_equal "tel:+15550100100", client.primary_phone.href
    assert_equal "mailto:Maria@Example.COM", client.primary_email.href

    as_business(@business) do
      bad = Client.new(display_name: "X", contact_methods_attributes: [ email("not-an-email"), phone("12") ])
      assert_not bad.valid?
      assert_equal [ [ "This isn't an email address" ], [ "This needs 7 to 15 digits" ] ],
                   bad.contact_methods.map { _1.errors.full_messages }, "as each row shows them"
    end
  end

  test "matching finds clients by email or phone regardless of formatting" do
    maria = create_client(contacts: [ phone("(555) 010-0100"), email("maria@example.com") ])
    as_business(@business) do
      assert_equal [ maria ], Client.matching(phones: [ "+1 555.010.0100" ]).to_a
      assert_equal [ maria ], Client.matching(emails: [ "MARIA@example.com" ]).to_a
      assert_empty Client.matching(phones: [ "0100" ]) # too short to suggest
      assert_empty Client.matching(emails: [ "" ], phones: [])
    end
    as_business(businesses(:two)) { assert_empty Client.matching(emails: [ "maria@example.com" ]) }
  end

  test "tags are lowercased, trimmed, unique and limited" do
    client = create_client(tag_list: "Commercial, weekly ,commercial,,")
    assert_equal %w[commercial weekly], client.tags
    assert_equal "commercial, weekly", client.tag_list
    as_business(@business) do
      client.tag_list = (1..21).map { "t#{_1}" }.join(",")
      assert_not client.valid?
      assert_includes client.errors[:tags], "can have at most 20"
    end
  end

  test "properties format their address and one can be billing" do
    client = create_client(properties: [ { address_line1: "1 Main St", address_line2: "Unit 4", city: "Austin", region: "TX", postal_code: "78701", billing: true },
                                         { address_line1: "9 Oak Ave", label: "Rental #2", access_notes: "Gate 1234" } ])
    billing = client.billing_property
    assert_equal "1 Main St, Unit 4, Austin, TX 78701", billing.one_line
    assert_equal billing, client.primary_property
    assert_equal "Rental #2", client.properties.second.name

    as_business(@business) do
      rental = client.properties.find_by!(label: "Rental #2")
      client.update!(properties_attributes: [ { id: rental.id, billing: "1" } ])
      assert_equal rental, client.reload.billing_property
      assert_not billing.reload.billing

      two_billing = Client.new(display_name: "X", contact_methods_attributes: [ phone("5550100100") ],
                               properties_attributes: [ { address_line1: "A", billing: true }, { address_line1: "B", billing: true } ])
      assert_not two_billing.valid?
      assert_includes two_billing.errors[:base], "Only one property can be the billing address."
    end
  end

  test "property needs a street address and a two-letter country" do
    as_business(@business) do
      property = Property.new(client: Client.new, city: "Austin", country: "usa")
      assert_not property.valid?
      assert property.errors.of_kind?(:address_line1, :blank)
      assert property.errors.of_kind?(:country, :invalid)
    end
  end

  test "archive, restore and delete" do
    client = create_client(properties: [ { address_line1: "1 Main" } ])
    as_business(@business) do
      client.archive!
      assert_includes Client.archived, client
      client.restore!
      assert_includes Client.active, client
      assert client.deletable?
      client.destroy!
      assert_equal 0, ClientContactMethod.count
      assert_equal 0, Property.count
    end
  end

  test "children take the client's business and stay inside it" do
    client = create_client(properties: [ { address_line1: "1 Main" } ])
    assert_equal [ @business.id ], (client.contact_methods + client.properties).map(&:business_id).uniq
    as_business(businesses(:two)) do
      assert_empty Client.all
      assert_empty Property.all
      assert_empty ClientContactMethod.all
    end
  end

  test "picker JSON" do
    client = create_client(properties: [ { address_line1: "1 Main", city: "Austin" } ], company_name: "Lopez Rentals")
    assert_equal({ uid: client.uid, name: "Maria Lopez", company: "Lopez Rentals", contact: "555-010-0100", property: "1 Main, Austin" },
                 client.as_picker_json)
  end
end
