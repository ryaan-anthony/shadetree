require "test_helper"

# INS-02: downloading a business's data as CSV.
class Admin::DataExportsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def download(table)
    get download_admin_data_exports_path(table)
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_equal "utf-8", response.charset
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert response.body.start_with?("\uFEFF"), "a byte-order mark, so Excel reads UTF-8"
    CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
  end

  test "Owners and Admins export; technicians can't" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_data_exports_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get download_admin_data_exports_path("clients") }
  end

  test "every table downloads with its documented columns, and each download is logged" do
    get admin_data_exports_path
    assert_select "#export-tables li", DataExport.tables.size
    assert_select "nav[aria-label=Settings] a[aria-current=page]", "Your data"
    DataExport.tables.each do |table|
      rows = download(table.key)
      assert_equal table.columns.map(&:header), rows.headers, table.key
      assert_match(/attachment; filename="#{@business.handle}-#{table.key}-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
    end
    assert_equal DataExport.tables.size, as_business(@business) { DataExport.where(requested_by: @owner).count }
    get admin_data_exports_path
    assert_select "#export-log li", DataExport.tables.size
    assert_select "#export-log li", /Payments.*#{@owner.full_name}/m
  end

  test "money, dates, times, lists and formulas are spreadsheet-friendly; only this business's data" do
    as_business(@business) do
      client = Client.create!(display_name: "=Maria Lopez", tags: %w[weekly vip], contact_methods_attributes: [ { kind: "email", value: "maria@example.com" }, { kind: "phone", value: "5550100100" } ])
      client.update_columns(created_at: Time.utc(2026, 3, 1, 3, 30))
      invoice = Invoice.start(client:)
      invoice.sync_line_items([ { "key" => "a", "name" => "Mowing", "quantity" => "2", "unit_price" => "620" } ])
      invoice.update!(tax_rates: [])
    end
    as_business(businesses(:two)) { Client.create!(display_name: "Their client", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ]) }

    clients = download("clients")
    assert_equal 1, clients.size
    row = clients.first
    assert_equal [ "'=Maria Lopez", "maria@example.com", "5550100100", "weekly; vip", "no", "2026-02-28 22:30" ],
                 row.values_at("Name", "Emails", "Phones", "Tags", "Tax exempt", "Created")
    invoice = download("invoices").first
    assert_equal [ "1240.00", "0.00", "1240.00", "USD" ], invoice.values_at("Total", "Paid", "Balance", "Currency")
    assert_no_match(/\A(due_on_receipt|net_\d+|custom)\z/, invoice["Payment terms"], "in words, as clients see them (owner, 2026-11-22)")
    line = download("invoice_lines").first
    assert_equal [ "Mowing", "2.0", "620.00" ], line.values_at("Item", "Quantity", "Unit price")
  end

  test "an unknown table isn't found" do
    get download_admin_data_exports_path("users")
    assert_response :not_found
  end

  test "money formatting handles negatives and small amounts" do
    assert_equal [ "0.05", "-12.30", "1240.00", nil ], [ 5, -1230, 124_000, nil ].map { DataExport::Table.money(_1, "USD") }
  end

  test "negative prices and phone numbers stay usable; formulas don't; rows come out in date order; taxes are broken down" do
    as_business(@business) do
      client = Client.create!(display_name: " =cmd", contact_methods_attributes: [ { kind: "phone", value: "+44 20 7946 0958" } ])
      invoice = Invoice.start(client:)
      invoice.sync_line_items([ { "key" => "a", "name" => "Credit", "quantity" => "1", "unit_price" => "-25" }, { "key" => "b", "name" => "Mowing", "quantity" => "1", "unit_price" => "100", "taxable" => "1" } ])
      invoice.update!(tax_rates: [ { "name" => "State", "percent" => "6.25" }, { "name" => "County", "percent" => "1" } ])
      job = Job.create!(client:, title: "Mowing")
      [ Date.new(2026, 11, 23), Date.new(2026, 11, 16) ].each { |on| job.visits.new(scheduled_on: on, timing: "anytime", duration_minutes: 60).schedule!(by: @owner) }
    end
    client = download("clients").first
    assert_equal [ "'=cmd", "+44 20 7946 0958" ], client.values_at("Name", "Phones")
    lines = download("invoice_lines")
    assert_equal [ "-25.00", "-25.00" ], lines.first.values_at("Unit price", "Line total")
    invoice = download("invoices").first
    assert_match(/State 6.25%: \d+\.\d\d; County 1%: \d+\.\d\d/, invoice["Taxes"])
    assert_equal %w[2026-11-16 2026-11-23], download("visits").map { _1["Date"] }
  end

  test "every table holds only this business's data" do
    as_business(businesses(:two)) do
      client = Client.create!(display_name: "Zed Other", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      quote = Quote.create!(client:, created_by: users(:two), title: "Theirs")
      ClientNote.create!(client:, user: users(:two), body: "Zed's note")
      assert quote
    end
    DataExport.tables.map(&:key).each { assert_no_match(/Zed|Theirs/, download(_1).to_s, _1) }
  end

  test "JOB-09: with split jobs on, the quote lines' claims, the job lines' quote lines and the work log, in new columns at the end" do
    get download_admin_data_exports_path("work_log")
    assert_response :not_found, "behind the flag"
    assert_not_includes download("quote_lines").headers, "In jobs"
    enable_feature(:split_jobs)
    job = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:)
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100" } ])
      quote.save!
      quote.update_columns(status: "approved")
      Job.from_quote!(quote, picks: { quote.line_items.first.id => "6" }).tap { _1.log_work!(user: @owner, by: @owner, totals: { _1.line_items.first.id => 4 }) }
    end
    quote_lines = download("quote_lines")
    assert_equal "In jobs", quote_lines.headers.last
    assert_equal "6.0", quote_lines.find { _1["Item"] == "Tree removal" }["In jobs"]
    job_lines = download("job_lines")
    assert_equal [ "Quote line position", "Claimed from quote", "Needs a price" ], job_lines.headers.last(3)
    assert_equal [ "0", "6.0", "no" ], job_lines.find { _1["Job number"] == job.number }.fields.last(3)
    claims = download("job_claims")
    assert_equal [ [ "Tree removal", job.number, "6.0", "yes" ] ], claims.map { _1.fields.values_at(2, 3, 6, 7) }
    log = download("work_log")
    assert_equal [ [ job.number, "Tree removal", @owner.full_name, "4.0", "logged" ] ], log.map { _1.fields.values_at(0, 1, 3, 4, 5) }
  end
end
