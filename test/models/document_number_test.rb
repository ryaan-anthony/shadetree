require "test_helper"

class DocumentNumberTest < ActiveSupport::TestCase
  test "numbers are sequential per business and per kind" do
    one, two = businesses(:one), businesses(:two)
    assert_equal "Q-0001", one.next_document_number(:quote)
    assert_equal "Q-0002", one.next_document_number(:quote)
    assert_equal "INV-0001", one.next_document_number(:invoice)
    assert_equal "Q-0001", two.next_document_number(:quote)
  end

  test "formats past four digits without truncating" do
    assert_equal "INV-12345", DocumentNumber.format(:invoice, 12_345)
  end

  test "unknown kinds raise" do
    assert_raises(DocumentNumber::UnknownKind) { businesses(:one).next_document_number(:receipt) }
  end
end

# Real concurrency needs real commits, so this test runs outside a transaction.
class DocumentNumberConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown { DocumentSequence.where(business: businesses(:one)).delete_all }

  test "concurrent requests never get the same number" do
    business = businesses(:one)
    threads = [ ActiveRecord::Base.connection_pool.size - 1, 2 ].max
    numbers = Array.new(threads) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { Array.new(20) { business.next_document_number(:invoice) } }
      end
    end.flat_map(&:value)

    assert_equal threads * 20, numbers.uniq.size
    assert_equal (1..threads * 20).map { DocumentNumber.format(:invoice, _1) }.sort, numbers.sort
  end
end
