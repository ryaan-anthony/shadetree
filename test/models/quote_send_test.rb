require "test_helper"

# QTE-04: marking a quote sent, and its usage event, exactly once (BIL-02 counts them).
class QuoteSendTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ]); _1.save! }
    end
  end

  test "the first send marks the quote sent and records usage; later sends don't change either" do
    as_business(@business) do
      @quote.mark_sent!(by: users(:one), channel: "link")
      sent_at = @quote.reload.sent_at
      travel(1.day) { @quote.mark_sent!(by: users(:one), channel: "email", recipient: "maria@example.com") }
      assert_equal sent_at, @quote.reload.sent_at
      assert_equal 1, UsageEvent.where(kind: "quote_sent", subject: @quote).count
      assert_equal sent_at, UsageEvent.find_by!(subject: @quote).occurred_at
      assert_equal 2, @quote.sends.count
    end
  end

  test "an answered quote can't be sent again" do
    as_business(@business) do
      @quote.update_column(:status, "approved")
      assert_raises(ArgumentError) { @quote.mark_sent!(by: users(:one), channel: "link") }
    end
  end

  test "usage is recorded once even if recorded twice" do
    as_business(@business) do
      assert UsageEvent.record!("quote_sent", @quote)
      assert_not UsageEvent.record!("quote_sent", @quote)
      assert_equal @business.id, UsageEvent.sole.business_id
      assert_raises(ArgumentError) { UsageEvent.record!("quote_viewed", @quote) }
    end
  end
end

# Concurrent first sends from two tabs: one usage event, one status change.
class QuoteSendConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two simultaneous first sends record usage once" do
    business = businesses(:one)
    quote = as_business(business) do
      client = Client.create!(display_name: "Race", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap { _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ]); _1.save! }
    end
    2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          as_business(business) { Quote.find(quote.id).mark_sent!(by: nil, channel: "link") }
        end
      end
    end.each(&:join)
    as_business(business) do
      assert_equal 1, UsageEvent.where(subject: quote).count
      assert_equal 2, quote.sends.count
    end
  ensure
    if quote
      as_business(business) do
        UsageEvent.where(subject: quote).delete_all
        ClientLink.where(linkable: quote).delete_all
        QuoteSend.where(quote_id: quote.id).delete_all
        client_id = quote.client_id
        Quote.where(id: quote.id).delete_all
        Client.find(client_id).destroy!
      end
      # Starting the quote took a number outside a transaction: give it back (as quote_numbering_test does).
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end
