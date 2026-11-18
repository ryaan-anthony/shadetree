require "test_helper"

# JOB-01 part 2: a job's own line items, added, changed and removed on the job form.
class Admin::JobLineItemsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", billing: true } ])
      @mulch = CatalogItem.create!(name: "Mulch", unit: "custom", custom_unit: "cu yd", unit_price: "78", taxable: false, description: "Hardwood")
      quote = Quote.start(client: @maria)
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "2", "unit" => "hour", "unit_price" => "90", "taxable" => "0" } ])
      quote.save!
      quote.update_columns(status: "approved")
      @quote = quote.reload
      @job = Job.from_quote!(@quote)
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def lines = as_business(@business) { @job.reload.line_items.map { [ _1.name, _1.quantity_label, _1.unit_price_cents ] } }

  def save(rows, **job)
    patch admin_job_path(@job), params: { job: { lock_version: as_business(@business) { @job.reload.lock_version }, line_items_attributes: rows, **job } }
  end

  test "change, add from the catalog, and remove lines; the quote keeps what was approved" do
    first = as_business(@business) { @job.line_items.first }
    get edit_admin_job_path(@job)
    assert_select "#job-items select option[value=?][data-price='78.00'][data-unit='cu yd']", @mulch.uid
    assert_select "#job-items template[data-kind=line]"

    save({ "0" => { id: first.id, name: "Leaf cleanup", quantity: "3", unit: "hour", unit_price: "90", taxable: "0" },
           "1" => { catalog_item_uid: @mulch.uid, name: "Mulch", description: "Hardwood", quantity: "6", unit: "cu yd", unit_price: "78", taxable: "0" },
           "2" => { name: "", description: "", unit_price: "", quantity: "1" } }) # an added row left empty
    assert_redirected_to admin_job_path(@job)
    assert_equal [ [ "Leaf cleanup", "3 hour", 9_000 ], [ "Mulch", "6 cu yd", 7_800 ] ], lines
    assert_equal 27_000 + 46_800, as_business(@business) { @job.reload.total_cents }
    assert_equal @mulch, as_business(@business) { @job.line_items.last.catalog_item }
    assert_equal 18_000, as_business(@business) { @quote.reload.total_cents }, "the quote doesn't change"

    second = as_business(@business) { @job.line_items.last }
    save({ "0" => { id: first.id, _destroy: "1" }, "1" => { id: second.id, name: "Mulch", quantity: "6", unit_price: "78" } })
    assert_equal [ [ "Mulch", "6 cu yd", 7_800 ] ], lines
    get admin_job_path(@job)
    assert_select "#job-lines", /Mulch/
  end

  test "a line needs a name and a sensible quantity; problems are shown on the row" do
    save({ "0" => { name: "", unit_price: "40", quantity: "1" }, "1" => { name: "Edging", quantity: "lots", unit_price: "5" } })
    assert_response :unprocessable_content
    assert_select ".banner-danger", /Some items need fixing/
    assert_select "#job-items .error-text", /needed for each item/
    assert_select "#job-items .error-text", /not a number/
    assert_select "input[value=lots]", 1, "what was typed is kept"
    assert_equal 1, lines.size
  end

  test "lines and catalog items from elsewhere can't be reached" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      job = Job.create!(client:, title: "Theirs")
      job.line_items.create!(name: "Theirs", quantity: 1, unit_price: "10")
    end
    their_item = as_business(businesses(:two)) { CatalogItem.create!(name: "Theirs", unit: "each", unit_price: "1") }

    save({ "0" => { id: theirs.id, name: "Mine now" } })
    assert_response :not_found
    save({ "0" => { catalog_item_uid: their_item.uid, name: "Borrowed", quantity: "1", unit_price: "1" } })
    assert_nil as_business(@business) { @job.reload.line_items.find_by(name: "Borrowed") }.catalog_item_id
    assert_equal "Theirs", as_business(businesses(:two)) { theirs.reload.name }
  end

  test "a job from scratch can start with items" do
    post admin_jobs_path, params: { job: { client: @maria.uid, property: @maria.properties.first.uid, title: "Mulch beds",
                                           line_items_attributes: { "0" => { catalog_item_uid: @mulch.uid, name: "Mulch", quantity: "4", unit: "cu yd", unit_price: "78", taxable: "0" } } } }
    job = as_business(@business) { Job.order(:id).last }
    assert_redirected_to admin_job_path(job)
    assert_equal 31_200, job.total_cents
  end

  test "a job has at most #{Job::MAX_LINES} items" do
    rows = (0..Job::MAX_LINES).to_h { [ _1.to_s, { name: "Line #{_1}", quantity: "1", unit_price: "1" } ] }
    save(rows)
    assert_response :unprocessable_content
    assert_select ".banner-danger", /at most #{Job::MAX_LINES} items/
  end
end
