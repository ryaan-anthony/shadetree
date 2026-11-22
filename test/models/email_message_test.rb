require "test_helper"

# #289: a client's emails are the ones about their own records, whichever kind of record the
# email was about, never another client's at the same address or another business's.
class EmailMessageTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
  end

  def email(related, to: "shared@example.com") = EmailMessage.create!(kind: "quote_sent", to:, related:)

  test "about_client: quotes, invoices, payments, jobs, visits and requests of this client only" do
    as_business(@business) do
      maria = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "email", value: "shared@example.com" } ])
      sam = Client.create!(display_name: "Sam", contact_methods_attributes: [ { kind: "email", value: "shared@example.com" } ])
      quote = Quote.start(client: maria).tap(&:save!)
      invoice = Invoice.start(client: maria).tap { _1.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "50" } ]); _1.save! }
      payment = invoice.payments.create!(business: @business, currency: "USD", payment_method: "cash", amount: "5", received_on: Date.current)
      job = Job.create!(client: maria, title: "Ants")
      visit = job.visits.create!(scheduled_on: Date.current, timing: "anytime", duration_minutes: 60)
      request = ServiceRequest.create!(client: maria, source: "phone", description: "Ants")
      mine = [ quote, invoice, payment, job, visit, request ].map { email(_1) }
      not_mine = [ email(Quote.start(client: sam).tap(&:save!)), email(nil), email(@business) ]

      assert_equal mine.map(&:id).sort, EmailMessage.about_client(maria).pluck(:id).sort
      assert_empty EmailMessage.about_client(sam).pluck(:id) & mine.map(&:id)
      assert_equal [ not_mine.first.id ], EmailMessage.about_client(sam).pluck(:id)
    end

    other = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "email", value: "shared@example.com" } ])
      email(Quote.start(client:).tap(&:save!))
      client
    end
    as_business(@business) { assert_empty EmailMessage.about_client(other).to_a, "another business's emails are never listed" }
  end
end
