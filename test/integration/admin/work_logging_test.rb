require "test_helper"

# JOB-09: everyone on a job's visits logs their own work from My day, lines
# added on site (a catalog service at its price, or an unpriced custom line the office prices
# before invoicing), the job page's "Marcus 4, Riley 2" and log, the office's corrections, and
# done means done.
class Admin::WorkLoggingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @marcus = member_with_role(:technician).tap { _1.update!(first_name: "Marcus") }
    @riley = member_with_role(:technician).tap { _1.update!(first_name: "Riley") }
    as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @job = Job.create!(client:, title: "Trees")
      @trees = @job.line_items.create!(name: "Tree removal", quantity: 6, unit_price: "100")
      @visit = @job.visits.new(scheduled_on: @business.today, timing: "exact", start_time: "09:00", duration_minutes: 60, assignee_ids: [ @marcus.id, @riley.id ]).tap { _1.schedule!(by: @owner) }
      @mowing = CatalogItem.create!(name: "Mowing", unit: "visit", unit_price: "45")
    end
  end

  def as(user)
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
    yield
  ensure
    sign_out user
  end

  def done(line) = as_business(@business) { WorkEntry.where(job_line_item_id: line.id).sum(:quantity).to_i }

  test "each person logs their own work from the visit; a change is a correction; the job page shows who did what" do
    as(@marcus) do
      get admin_my_visit_path(@visit)
      assert_select "#visit-work input[name=?]", "done[#{@trees.id}]"
      patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "4" } }
      assert_equal "Saved what you did.", flash[:notice]
    end
    as(@riley) { patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "2" } } }
    as(@marcus) do
      patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "3" } }
      get admin_my_visit_path(@visit)
      assert_select "#visit-work-lines", /logged Marcus 3, Riley 2/
      assert_select "input[name=?][value=?]", "done[#{@trees.id}]", "3" # your own total
    end
    assert_equal [ 4, 2, -1 ], as_business(@business) { WorkEntry.order(:id).pluck(:quantity).map(&:to_i) }, "only ever added"
    assert_equal 5, done(@trees)

    as(@owner) do
      get admin_job_path(@job)
      assert_select "#job-lines", /Logged: Marcus 3, Riley 2/
      assert_select "#work-log-entries li", 3
      assert_select "#job-complete input[name=?][value='5']", "done[#{@trees.id}]" # completion starts at the logged totals
    end
  end

  test "the office corrects anyone's work" do
    as(@marcus) { patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "4" } } }
    as(@owner) do
      patch work_log_admin_job_path(@job), params: { log: { "#{@trees.id}-#{@marcus.id}-#{@visit.id}" => "6" } }
      assert_redirected_to admin_job_path(@job, anchor: "work-log")
    end
    entry = as_business(@business) { WorkEntry.order(:id).last }
    assert_equal [ 2, @marcus.id, @owner.id ], [ entry.quantity.to_i, entry.user_id, entry.recorded_by_id ]
  end

  test "lines added on site: a service at its price, or a custom line the office prices before invoicing" do
    as(@riley) do
      post work_line_admin_my_visit_path(@visit), params: { catalog_item: @mowing.uid, quantity: "1" }
      post work_line_admin_my_visit_path(@visit), params: { name: "Wasp nest", quantity: "1" }
      post work_line_admin_my_visit_path(@visit), params: { quantity: "1" }
      assert_equal "Choose a service or type what was done.", flash[:alert]
    end
    mowing, nest = as_business(@business) { @job.reload.line_items.drop(1) }
    assert_equal [ [ "Mowing", 4_500, false ], [ "Wasp nest", 0, true ] ], [ mowing, nest ].map { [ _1.name, _1.unit_price_cents, _1.price_pending ] }
    assert_equal [ 1, 1 ], [ done(mowing), done(nest) ]

    as(@owner) do
      get admin_job_path(@job)
      assert_select "#job-lines", /Wasp nest\s*Needs a price/
      assert_select "#job-complete input[name=?][required]:not([value])", "prices[#{nest.id}]"
      rows = as_business(@business) { @job.reload.line_items.each_with_index.to_h { |line, index| [ index.to_s, { id: line.id, name: line.name, quantity: line.quantity_for_form, unit_price: line.unit_price.to_s } ] } }
      patch admin_job_path(@job), params: { job: { line_items_attributes: rows } }
      assert as_business(@business) { nest.reload.price_pending }, "saving the form as is doesn't price it"
      get edit_admin_job_path(@job)
      assert_select "fieldset", /Needs a price/
      patch complete_admin_job_path(@job)
      assert_equal "Price Wasp nest before completing (type 0 for no charge).", flash[:alert]
      patch complete_admin_job_path(@job), params: { prices: { nest.id => "0" } }
      assert_equal [ "completed", 0, false ], as_business(@business) { [ @job.reload.status, *nest.reload.values_at(:unit_price_cents, :price_pending) ] }
      post admin_job_invoices_path(@job)
      assert_match "started from job #{@job.number}", flash[:notice]
    end
  end

  test "a price typed on the job form prices a line added on site" do
    as(@riley) { post work_line_admin_my_visit_path(@visit), params: { name: "Wasp nest", quantity: "1" } }
    nest = as_business(@business) { @job.reload.line_items.last }
    as(@owner) do
      rows = as_business(@business) { @job.reload.line_items.each_with_index.to_h { |line, index| [ index.to_s, { id: line.id, name: line.name, quantity: line.quantity_for_form, unit_price: line == nest ? "60" : line.unit_price.to_s } ] } }
      patch admin_job_path(@job), params: { job: { line_items_attributes: rows } }
    end
    assert_equal [ 6_000, false ], as_business(@business) { nest.reload.values_at(:unit_price_cents, :price_pending) }
  end

  test "done means done: a completed job's work can't change" do
    as_business(@business) { @job.complete!(by: @owner) }
    as(@marcus) do
      get admin_my_visit_path(@visit)
      assert_select "#visit-work input", 0
      patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "4" } }
      assert_match "is completed, so its work can't change", flash[:alert]
      post work_line_admin_my_visit_path(@visit), params: { name: "More", quantity: "1" }
      assert_match "is completed, so its work can't change", flash[:alert]
    end
    assert_equal 0, as_business(@business) { WorkEntry.count }
  end

  test "only people on the visit log its work; another business's visits aren't found" do
    other = member_with_role(:technician)
    as(other) do
      patch work_admin_my_visit_path(@visit), params: { done: { @trees.id => "4" } }
      assert_response :not_found
    end
    as(@marcus) do
      theirs = as_business(businesses(:two)) do
        client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
        Job.create!(client:, title: "Theirs").visits.new(scheduled_on: @business.today, assignee_ids: []).tap { _1.schedule!(by: nil) }
      end
      assert_not_found_across_businesses { patch work_admin_my_visit_path(theirs), params: { done: {} } }
    end
    assert_permission_matrix(owner: true, admin: true, technician: false) { patch work_log_admin_job_path(@job), params: { log: {} } }
  end
end
