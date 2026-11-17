require "test_helper"

# QTE-06: a quote's activity history, built from what each step records.
class QuoteActivityTest < ActiveSupport::TestCase
  test "lists sends, responses and staff actions newest first, grouping views between them" do
    business = businesses(:one)
    as_business(business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: users(:one))
      quote.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ])
      quote.save!
      travel(1.hour) { quote.mark_sent!(by: users(:one), channel: "link") }
      link = quote.client_link!
      travel(2.hours) { link.record_view! }
      travel(3.hours) { link.record_view! }
      travel(4.hours) { quote.record_response!(:request_changes, link:, message: "Skip the side yard") }
      travel(5.hours) { link.record_view! }
      travel(6.hours) { quote.archive!(by: users(:one)) }

      titles = QuoteActivity.for(quote).map(&:title)
      name = users(:one).full_name
      assert_equal [ "Archived by #{name}", "Viewed by the client", "Changes requested by the client", "Viewed 2 times",
                     "Link copied by #{name}", "Created by #{name}" ], titles
      assert QuoteActivity.for(quote).find { _1.title == "Viewed 2 times" }.since
    end
  end
end
