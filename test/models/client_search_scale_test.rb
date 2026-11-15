require "test_helper"

# CLI-02: the list stays responsive at 10,000 clients in one business.
class ClientSearchScaleTest < ActiveSupport::TestCase
  CLIENTS = 10_000

  setup do
    @business = businesses(:one)
    now = Time.current
    rows = Array.new(CLIENTS) do |i|
      name = "Client #{i.to_s.rjust(5, "0")}"
      phone = format("555%07d", i)
      { business_id: @business.id, uid: SecureRandom.base58(12), display_name: name, tags: (i % 10).zero? ? [ "commercial" ] : [],
        search_text: "#{name} #{phone} #{i} main street austin tx".downcase, created_at: now, updated_at: now, last_activity_at: now - i.minutes }
    end
    as_business(@business) { rows.each_slice(2_000) { Client.insert_all!(_1) } }
    ActiveRecord::Base.connection.execute("ANALYZE clients")
  end

  test "search, filter and sort a page in well under a second, with the trigram index" do
    as_business(@business) do
      [ -> { Client.active.search("client 0423").sorted("name") },
        -> { Client.active.search("5550004").sorted("activity") },
        -> { Client.active.tagged("commercial").sorted("recent") },
        -> { Client.active.sorted("name") } ].each do |query|
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        query.call.count
        query.call.includes(:contact_methods, :properties).offset(50).limit(50).to_a
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        assert_operator elapsed, :<, 0.5, "query took #{(elapsed * 1000).round}ms"
      end
      assert_equal 11, Client.search("client 0423").count # 04230-04239 and 00423
      assert_equal 1, Client.search("555-000-4231").count
    end

    # With one business the planner may prefer business_id and filter; across many businesses
    # it needs the trigram index, so check the index can serve these "contains" patterns.
    plan = ActiveRecord::Base.connection.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
      Tenancy.across_businesses(reason: "test: query plan") { Client.where("clients.search_text LIKE ?", "%0423%").explain.inspect }
    end
    assert_match "index_clients_on_search_text", plan
  end
end
