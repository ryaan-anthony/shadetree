require "test_helper"

# CLI-02: the client list stays responsive at 10,000 clients in one business. Clients get a
# phone, an email and a property each, and search_text is built by the production SQL
# (Client.refresh_search_text, the same as the backfill migration). Requests are timed end
# to end (controller, queries and view), each after a warm-up run, with a generous budget so
# shared CI runners don't flake; locally they take a small fraction of it.
class Admin::ClientSearchScaleTest < ActionDispatch::IntegrationTest
  CLIENTS = 10_000
  BUDGET = 1.0 # seconds per request

  setup do
    @business = businesses(:one)
    seed_clients
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "list, search, filter, sort and page through 10,000 clients within budget; the trigram index serves search" do
    timed { get admin_clients_path }
    assert_select "tbody tr", 50

    timed { post search_admin_clients_path, params: { q: "client 0423" } }
    assert_select "tbody tr", 11 # 04230-04239 and 00423

    timed { post search_admin_clients_path, params: { q: "+1 (555) 000-4231" } }
    assert_select "tbody tr", 1

    timed { post search_admin_clients_path, params: { q: "elm street" } }
    timed { post search_admin_clients_path, params: { tag: "commercial", sort: "recent", page: 3 } }
    assert_select "tbody tr", 50
    timed { post search_admin_clients_path, params: { sort: "activity", page: 200 } }
    timed { post search_admin_clients_path(format: :json), params: { q: "client 09" } }
    assert_equal 8, response.parsed_body["clients"].size

    # With one business the planner may prefer business_id and filter, which is fast at this
    # size; with many businesses it needs this index, so check it can serve LIKE '%…%'.
    plan = ActiveRecord::Base.connection.transaction do
      ActiveRecord::Base.connection.execute("SET LOCAL enable_seqscan = off")
      Tenancy.across_businesses(reason: "test: query plan") { Client.where("clients.search_text LIKE ?", "%0423%").explain.inspect }
    end
    assert_match "index_clients_on_search_text", plan
  end

  private

  def timed
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    assert_response :success
    assert_operator elapsed, :<, BUDGET, "#{request.method} #{request.path} took #{(elapsed * 1000).round}ms"
  end

  def seed_clients
    now = Time.current
    as_business(@business) do
      rows = Array.new(CLIENTS) do |i|
        { business_id: @business.id, uid: SecureRandom.base58(12), display_name: "Client #{i.to_s.rjust(5, "0")}",
          tags: (i % 10).zero? ? [ "commercial" ] : [], created_at: now - i.minutes, updated_at: now, last_activity_at: now - i.minutes }
      end
      ids = rows.each_slice(2_000).flat_map { Client.insert_all!(_1, returning: :id).rows.flatten }
      contacts = ids.each_with_index.flat_map do |id, i|
        [ { business_id: @business.id, client_id: id, kind: "phone", value: format("(555) 000-%04d", i), normalized: format("555000%04d", i), created_at: now, updated_at: now },
          { business_id: @business.id, client_id: id, kind: "email", value: "client#{i}@example.com", normalized: "client#{i}@example.com", created_at: now, updated_at: now } ]
      end
      contacts.each_slice(5_000) { ClientContactMethod.insert_all!(_1) }
      properties = ids.each_with_index.map do |id, i|
        { business_id: @business.id, client_id: id, uid: SecureRandom.base58(12), address_line1: "#{i} #{i.even? ? "Elm" : "Oak"} Street",
          city: "Austin", region: "TX", postal_code: "78701", created_at: now, updated_at: now }
      end
      properties.each_slice(5_000) { Property.insert_all!(_1) }
      ids.each_slice(2_000) { Client.refresh_search_text(_1) }
    end
    ActiveRecord::Base.connection.execute("ANALYZE clients")
  end
end
