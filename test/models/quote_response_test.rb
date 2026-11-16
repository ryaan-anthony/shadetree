require "test_helper"

# QTE-05: recording a client's answer to a quote.
class QuoteResponseTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ])
        _1.save!
        _1.mark_sent!(by: nil, channel: "link")
      end
    end
  end

  test "the snapshot digest doesn't depend on key order" do
    assert_equal QuoteResponse.digest({ "b" => 1, "a" => { "d" => 2, "c" => [ { "f" => 3, "e" => 4 } ] } }),
                 QuoteResponse.digest({ "a" => { "c" => [ { "e" => 4, "f" => 3 } ], "d" => 2 }, "b" => 1 })
  end

  test "staff can record an approval with a note, also after a change request, but not on an expired quote" do
    as_business(@business) do
      assert_raises(ActiveRecord::RecordInvalid) { @quote.record_response!(:approve, by: users(:one), signer_name: "Maria Lopez") }
      @quote.record_response!(:request_changes, message: "Skip the side yard")
      approval = @quote.record_response!(:approve, by: users(:one), signer_name: "Maria Lopez", message: "Agreed on the phone")
      assert_equal [ "approved", users(:one) ], [ @quote.reload.status, approval.recorded_by ]
      assert approval.snapshot_intact?

      other = Quote.start(client: @quote.client).tap { _1.update!(expires_on: @business.today - 1) }
      other.update_columns(status: "sent")
      assert_raises(Quote::NotOpen) { other.record_response!(:approve, by: users(:one), signer_name: "M", message: "Phone") }
    end
  end

  test "a client can't approve after asking for changes, and nobody can change an approved quote's answer" do
    as_business(@business) do
      @quote.record_response!(:request_changes, message: "Skip the side yard")
      assert_raises(Quote::NotOpen) { @quote.record_response!(:approve, signer_name: "Maria", terms_accepted: "1") }
      @quote.record_response!(:approve, by: users(:one), signer_name: "Maria", message: "Phone")
      assert_raises(Quote::NotOpen) { @quote.record_response!(:decline) }
      assert_raises(Quote::NotOpen) { @quote.record_response!(:approve, by: users(:one), signer_name: "Maria", message: "Again") }
    end
  end
end

# Two devices approving at the same moment: one approval.
class QuoteResponseConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "simultaneous approvals record one" do
    business = businesses(:one)
    quote = as_business(business) do
      client = Client.create!(display_name: "Race", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client:).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "1", "unit_price" => "40" } ])
        _1.save!
        _1.update_columns(status: "sent")
      end
    end
    results = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          as_business(business) { Quote.find(quote.id).record_response!(:approve, signer_name: "Race", terms_accepted: "1") && :approved }
        rescue Quote::NotOpen
          :refused
        end
      end
    end.map(&:value)
    assert_equal %i[approved refused], results.sort
    assert_equal 1, as_business(business) { QuoteResponse.where(quote_id: quote.id).count }
  ensure
    if quote
      as_business(business) do
        QuoteResponse.where(quote_id: quote.id).delete_all
        client_id = quote.client_id
        Quote.where(id: quote.id).delete_all
        Client.find(client_id).destroy!
      end
      ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{business.id.to_i}")
    end
  end
end
