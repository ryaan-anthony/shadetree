require "test_helper"

# PAY-02: Invoice#mark_sent! and the dates an invoice goes out with.
class InvoiceMarkSentTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @invoice = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Invoice.start(client:).tap do |invoice|
        invoice.sync_line_items([ { "key" => "a", "name" => "Work", "quantity" => "1", "unit_price" => "100" } ])
        invoice.save!
      end
    end
  end

  test "paid, void and empty invoices can't be sent; a sent one can be sent again without changing when it was first sent" do
    as_business(@business) do
      @invoice.mark_sent!(by: @owner, channel: "link")
      first = @invoice.reload.sent_at
      travel 1.hour do
        @invoice.mark_sent!(by: @owner, channel: "link")
      end
      assert_equal first, @invoice.reload.sent_at
      assert_equal 2, @invoice.sends.count

      %w[paid void].each do |status|
        @invoice.update_columns(status:)
        assert_raises(ArgumentError) { @invoice.reload.mark_sent!(by: @owner, channel: "link") }
      end
      @invoice.update_columns(status: "draft", sent_at: nil)
      @invoice.line_items.delete_all
      assert_raises(ArgumentError) { @invoice.reload.mark_sent!(by: @owner, channel: "link") }
    end
  end

  test "dates when sent: a stale first send is issued today; revisions and current drafts keep theirs" do
    as_business(@business) do
      today = @business.today
      @invoice.update_columns(issued_on: today, due_on: today + 15)
      assert_equal [ today, today + 15 ], @invoice.reload.dates_when_sent
      @invoice.update_columns(issued_on: today - 40, due_on: today - 10, payment_terms: "custom")
      assert_equal [ today, today ], @invoice.reload.dates_when_sent, "a passed custom date becomes today"
      @invoice.update_columns(sent_at: 1.month.ago, revision: 2)
      assert_equal [ today - 40, today - 10 ], @invoice.reload.dates_when_sent
    end
  end
end
