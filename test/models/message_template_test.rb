require "test_helper"

# NTF-03: templates render placeholders, refuse unknown ones and markup, and match the defaults.
class MessageTemplateTest < ActiveSupport::TestCase
  setup { @business = businesses(:one) }

  def template(**attributes) = as_business(@business) { MessageTemplate.new(kind: "quote_sent", subject: "Quote {{quote_number}}", body: "Hi {{client_first_name}}", **attributes) }

  test "placeholders are filled in; unknown or missing values become nothing" do
    assert_equal "Hi Maria, Q-1 !", MessageTemplate.render("Hi {{ client_first_name }}, {{quote_number}} {{missing}}!", { "client_first_name" => "Maria", "quote_number" => "Q-1" })
  end

  test "an unknown placeholder or any markup is refused, with a message that says which" do
    record = template(body: "Hi {{client_first_name}} {{nope}} {{link}}")
    assert_not record.valid?
    assert_includes record.errors[:base].first, "{{nope}} and {{link}} aren't placeholders for this message"
    record = template(body: "Hi <script>alert(1)</script>")
    assert_not record.valid?
    assert_match(/plain text/, record.errors[:base].to_sentence)
    assert template(body: "Prices < $50 and 3 > 2").valid?, "a lone < isn't markup"
  end

  test "every editable message is a client-facing catalog entry, and its default uses only its own placeholders" do
    MessageTemplate::DEFINITIONS.each_value do |definition|
      assert EmailCatalog.find(definition.kind).client_facing, definition.kind
      record = as_business(@business) { MessageTemplate.new(kind: definition.kind, subject: definition.subject, body: definition.body) }
      assert record.valid?, "#{definition.kind}: #{record.errors.full_messages.to_sentence}"
      assert (definition.placeholders - MessageTemplate::PLACEHOLDERS.keys).empty?
    end
  end

  test "one template per message per business" do
    as_business(@business) { MessageTemplate.create!(kind: "quote_sent", subject: "A", body: "B") }
    assert_not template.valid?
    assert as_business(businesses(:two)) { MessageTemplate.new(kind: "quote_sent", subject: "A", body: "B").valid? }
  end
end
