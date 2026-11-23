require "test_helper"

# JOB-09 (split_jobs flag): Create job's picker, a resubmitted picker, refusals, the quote page's
# Jobs card and Primary, the job page's "From Q-0004: 1 of 2 services", adding to-do work,
# confirming what was done, the job form's limit, reopening, roles and tenancy.
class Admin::JobPickerTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: users(:one))
      quote.title = "Yard work"
      quote.sync_line_items([ { "key" => "t", "name" => "Tree removal", "quantity" => "10", "unit_price" => "100" },
                              { "key" => "g", "name" => "Gutters", "quantity" => "1", "unit_price" => "200" } ])
      quote.save!
      quote.update_columns(status: "approved")
      quote
    end
    enable_feature(:split_jobs)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def pick(trees: nil, gutters: nil, token: "tok-#{SecureRandom.hex(4)}")
    picks = {}
    picks["t"] = { take: "1", quantity: trees.to_s } if trees
    picks["g"] = { take: "1", quantity: gutters.to_s } if gutters
    post admin_quote_job_path(@quote), params: { picks:, picker_token: token }
  end

  def jobs = as_business(@business) { @quote.jobs.reload.to_a }

  test "Create job opens the picker, each line ticked at what's to do; a job takes the picked part" do
    get admin_quote_path(@quote)
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    get new_admin_quote_job_path(@quote)
    assert_response :success
    assert_select "input[type=checkbox][name=?][checked]", "picks[t][take]"
    assert_select "input[name=?][value='10'][max='10']", "picks[t][quantity]"
    assert_select "#pick-t", /10 of 10 to do/
    assert_select "input[name=picker_token]", 1

    pick(trees: 6, token: "same")
    job = jobs.sole
    assert_redirected_to admin_job_path(job)
    assert_equal "Job #{job.number} created from quote #{@quote.number}.", flash[:notice]
    assert_equal "Tree removal (6 of 10)", job.title
    follow_redirect!
    pick(trees: 6, token: "same")
    assert_redirected_to admin_job_path(job), "a resubmitted picker opens the job it made"
    assert_nil flash[:notice]
    assert_equal 1, jobs.size

    get new_admin_quote_job_path(@quote)
    assert_select "#pick-t", /4 of 10 to do · #{job.number} has 6/
    pick(trees: 5)
    assert_redirected_to new_admin_quote_job_path(@quote)
    assert_equal "Couldn't make a job from quote #{@quote.number}: Tree removal: 4 of 10 to do (#{job.number} has 6), not 5.", flash[:alert]
    pick
    assert_match "Choose at least one line to do.", flash[:alert]
  end

  test "the quote page lists its jobs per line; the job page says what it takes" do
    pick(trees: 6)
    pick(trees: 4, gutters: 1)
    first, second = jobs
    get admin_quote_path(@quote)
    assert_select "a[href='#jobs']", "Jobs (2)"
    assert_select "#jobs h2", "Jobs (2)"
    assert_select "#quote-line-jobs tbody tr:nth-child(1)", /Tree removal.*#{first.number} 6 \(unscheduled\), #{second.number} 4 \(unscheduled\).*0/m
    assert_select "a[href=?]", new_admin_quote_job_path(@quote), count: 0, message: "nothing left to do"
    assert_select "form[action=?]", admin_quote_invoices_path(@quote), count: 0, message: "no completed work yet: nothing to bill (PAY-06)"
    as_business(@business) { first.complete!(by: users(:one)) }
    get admin_quote_path(@quote)
    assert_select "form[action=?] button.btn-primary", admin_quote_invoices_path(@quote), /Create invoice/, "completed work to bill"

    get admin_job_path(first)
    assert_match(/from #{@quote.number}: 1 of 2 services/, css_select("main").text)
  end

  test "to-do work can be added to an open job" do
    pick(trees: 3)
    job = jobs.sole
    get admin_job_path(job)
    assert_select "a[href=?]", new_admin_job_work_path(job), /Add to-do work/
    get new_admin_job_work_path(job)
    assert_select "#pick-t", /7 of 10 to do/
    post admin_job_work_path(job), params: { picks: { "t" => { take: "1", quantity: "2" }, "g" => { take: "1", quantity: "1" } } }
    assert_redirected_to admin_job_path(job)
    assert_equal [ [ "Tree removal", 5 ], [ "Gutters", 1 ] ], as_business(@business) { job.reload.line_items.map { [ _1.name, _1.quantity.to_i ] } }
  end

  test "completing confirms what was done; a cancelled job's work can be booked again, and its reopen is then refused" do
    pick(trees: 6)
    job = jobs.sole
    trees = as_business(@business) { job.line_items.first }
    get admin_job_path(job)
    assert_select "#job-complete input[name=?][value='6']", "done[#{trees.id}]"
    patch complete_admin_job_path(job), params: { done: { trees.id => "5" } }
    assert_redirected_to admin_job_path(job)
    assert_equal [ "completed", 5 ], as_business(@business) { [ job.reload.status, trees.reload.quantity.to_i ] }

    other = as_business(@business) { Job.from_quote!(@quote, picks: { trees.claim.quote_line_item_id => "4" }) }
    patch cancel_admin_job_path(other)
    pick(trees: 4)
    patch reopen_admin_job_path(other)
    assert_match "#{other.number} can't be reopened while its work is in another job.", flash[:alert]
  end

  test "the job form can't take more than the quote has to do" do
    pick(trees: 6)
    job = jobs.sole
    trees = as_business(@business) { job.line_items.first }
    patch admin_job_path(job), params: { job: { line_items_attributes: { "0" => { id: trees.id, name: "Tree removal", quantity: "12", unit_price: "100" } } } }
    assert_response :unprocessable_content
    assert_select ".banner-danger", /Tree removal: 4 of 10 to do \(#{job.number} has 6\), not 6\./
    assert_equal 6, as_business(@business) { trees.reload.quantity.to_i }
  end

  test "Create job is the Primary while work is to do and nothing completed is unbilled" do
    pick(trees: 6)
    get admin_quote_path(@quote)
    assert_select "a.btn-primary[href=?]", new_admin_quote_job_path(@quote), /Create job/
    assert_select "form[action=?]", admin_quote_invoices_path(@quote), count: 0, message: "nothing completed to bill (PAY-06)"
  end

  test "a resubmitted picker whose job was cancelled shows the picker again" do
    pick(trees: 3, token: "again")
    patch cancel_admin_job_path(jobs.sole)
    pick(trees: 3, token: "again")
    assert_redirected_to new_admin_quote_job_path(@quote)
    assert_match "was cancelled. Choose the work again.", flash[:alert]
  end

  test "flag off: the quote page makes its one job straight away, as before" do
    disable_feature(:split_jobs)
    get admin_quote_path(@quote)
    assert_select "form[action=?] button", admin_quote_job_path(@quote), /Create job/
    get new_admin_quote_job_path(@quote)
    assert_redirected_to admin_quote_path(@quote)
  end

  test "only office access makes jobs, and another business's quotes aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_quote_job_path(@quote) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_quote_job_path(@quote), params: { picks: { "t" => { take: "1", quantity: "1" } } } }
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Quote.start(client:).tap { _1.update_columns(status: "approved") }
    end
    assert_not_found_across_businesses { get new_admin_quote_job_path(theirs) }
    assert_not_found_across_businesses { post admin_quote_job_path(theirs) }
  end

  test "members who only quote their assigned requests (QTE-07/08) see no job" do
    pick(trees: 6)
    sign_out :user
    as_technician do
      get admin_quote_path(@quote)
      assert_response :not_found
      get admin_job_path(jobs.sole)
      assert_response :forbidden
      get new_admin_job_work_path(jobs.sole)
      assert_response :forbidden
    end
  end
end
