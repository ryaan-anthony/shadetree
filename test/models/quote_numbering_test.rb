require "test_helper"

# QTE-01: quote numbers stay unique when drafts are started at the same moment.
class QuoteNumberingTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @business = businesses(:one)
    @client = as_business(@business) do
      Client.create!(display_name: "Concurrent Co", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
    end
  end

  teardown do
    Tenancy.across_businesses(reason: "test cleanup") do
      Quote.unscoped.where(business: @business).delete_all
      Client.unscoped.where(id: @client.id).destroy_all
    end
    ActiveRecord::Base.connection.execute("DELETE FROM document_sequences WHERE business_id = #{@business.id.to_i}")
  end

  test "twenty drafts started at once by four sessions get twenty different, gap-free numbers" do
    threads = Array.new(4) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Tenancy.with_business(@business) { Array.new(5) { Quote.start(client: Client.find(@client.id)).number } }
        end
      end
    end
    numbers = threads.flat_map(&:value)
    assert_equal 20, numbers.uniq.size
    assert_equal (1..20).map { format("Q-%04d", _1) }, numbers.sort
  end
end
