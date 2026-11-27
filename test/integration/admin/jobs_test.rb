require "test_helper"

# JOB-01: the job list, a job's page, jobs from quotes and from scratch, and finishing one.
class Admin::JobsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", billing: true, access_notes: "Gate code 4417" } ])
      @job = Job.create!(client: @maria, property: @maria.properties.first, title: "Gutter clean", instructions: "Ladder on the left side")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def approved_quote
    as_business(@business) do
      quote = Quote.start(client: @maria, created_by: users(:one))
      quote.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180" } ])
      quote.save!
      quote.mark_sent!(by: users(:one), channel: "link")
      quote.update_columns(status: "approved")
      quote
    end
  end

  test "only Owners and Admins see jobs, and another business's aren't found" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_jobs_path }
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_job_path(@job) }
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_jobs_path, params: { job: { client: @maria.uid, title: "x" } } }
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs") # no properties, so none needed
    end
    assert_not_found_across_businesses { get admin_job_path(theirs) }
    assert_not_found_across_businesses { patch complete_admin_job_path(theirs) }
    assert_not_found_across_businesses { patch admin_job_path(theirs), params: { job: { title: "Mine" } } }
  end

  test "the job page shows the client, property, access notes, instructions and items" do
    get admin_job_path(@job)
    assert_response :success
    assert_select "h1", "Gutter clean"
    assert_select "aside", /Maria Lopez.*12 Elm St.*Gate code 4417.*5550100100/m
    assert_select "#job-instructions", "Ladder on the left side"
    assert_select "main", /No items/
  end

  test "an approved quote's page makes its job once, then links to it" do
    quote = approved_quote
    get admin_quote_path(quote)
    assert_select "a[href=?]", new_admin_quote_job_path(quote), /Create job/
    get new_admin_quote_job_path(quote)
    token = css_select("input[name=picker_token]").first["value"]
    picks = as_business(@business) { quote.line_items.to_h { [ _1.key, { take: "1", quantity: _1.quantity.to_i.to_s } ] } }

    post admin_quote_job_path(quote), params: { picker_token: token, picks: }
    job = as_business(@business) { quote.reload.jobs.first }
    assert_redirected_to admin_job_path(job)
    post admin_quote_job_path(quote), params: { picker_token: token, picks: } # the same picker again
    assert_redirected_to admin_job_path(job)
    assert_equal 2, as_business(@business) { Job.count }

    get admin_job_path(job)
    assert_select "a[href=?]", admin_quote_path(quote), /#{quote.number}/
    assert_select "#job-lines", /Leaf cleanup/
    get admin_quote_path(quote)
    assert_select "a[href=?]", admin_job_path(job), /Job #{job.number}/
  end

  test "a quote that isn't approved can't become a job" do
    quote = approved_quote
    quote.update_columns(status: "sent")
    post admin_quote_job_path(quote)
    assert_redirected_to admin_quote_path(quote)
    assert_match "Only an approved quote", flash[:alert]
  end

  test "a job from scratch, then edited" do
    get new_admin_job_path(client: @maria.uid)
    assert_select "select[name='job[property]'] option[selected]", /12 Elm St/

    post admin_jobs_path, params: { job: { client: "", title: "Hedges" } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Choose a client/

    post admin_jobs_path, params: { job: { client: @maria.uid, property: @maria.properties.first.uid, title: "Hedges", instructions: "Front only", internal_notes: "Cash" } }
    job = as_business(@business) { Job.order(:id).last }
    assert_redirected_to admin_job_path(job)
    assert_equal [ "Hedges", "Front only", "Cash", users(:one) ], [ job.title, job.instructions, job.internal_notes, job.created_by ]

    patch admin_job_path(job), params: { job: { title: "Hedges and shrubs", lock_version: job.lock_version } }
    assert_redirected_to admin_job_path(job)
    assert_equal "Hedges and shrubs", as_business(@business) { job.reload.title }
    patch admin_job_path(job), params: { job: { title: "Stale tab", lock_version: 0 } }
    assert_redirected_to edit_admin_job_path(job)
    assert_match "changed in another tab", flash[:alert]
    patch admin_job_path(job), params: { job: { property: "" } }
    assert_response :unprocessable_content, "the client has a property, so the job needs one"
    patch admin_job_path(job), params: { job: { title: "" } }
    assert_response :unprocessable_content

    as_business(@business) { job.reload.complete!(by: nil) }
    get edit_admin_job_path(job)
    assert_redirected_to admin_job_path(job)
    assert_match "Reopen it to make changes", flash[:alert]
  end

  test "an archived client's quote says to restore them" do
    quote = approved_quote
    as_business(@business) { @maria.archive! }
    post admin_quote_job_path(quote)
    assert_match "Maria Lopez is archived. Restore them first.", flash[:alert]
  end

  test "complete, cancel with a reason, and reopen" do
    as_business(@business) { @job.line_items.create!(name: "Gutters", quantity: 1, unit_price: "80", position: 0) }
    patch complete_admin_job_path(@job)
    assert_redirected_to admin_job_path(@job)
    follow_redirect!
    assert_select ".banner-success", /Completed.*Ready to invoice/m
    assert_select "form[action=?]", reopen_admin_job_path(@job)

    patch cancel_admin_job_path(@job), params: { reason: "Moved" }
    assert_match "already completed", flash[:alert]

    patch reopen_admin_job_path(@job)
    patch cancel_admin_job_path(@job), params: { reason: "Moved away" }
    follow_redirect!
    assert_select ".banner-warning", /Cancelled.*“Moved away”/m
  end

  test "the list filters, searches and counts" do
    done = as_business(@business) { Job.create!(client: @maria, property: @maria.primary_property, title: "Patio").tap { _1.complete!(by: nil) } }
    get admin_jobs_path
    assert_select "tbody tr", 1
    assert_select "#job-#{@job.uid}", /Gutter clean.*Maria Lopez.*12 Elm St.*Unscheduled.*Added directly/m
    assert_select "button[value=completed]", /Completed\s*1/

    post search_admin_jobs_path, params: { filter: "completed" }
    assert_select "#job-#{done.uid}"
    assert_select "#job-#{@job.uid}", 0

    post search_admin_jobs_path, params: { filter: "all", q: "gutter" }
    assert_select "tbody tr", 1
    post search_admin_jobs_path, params: { filter: "all", q: "nothing like it" }
    assert_select ".card", /No jobs match/
  end

  test "jobs appear on the client's page" do
    get admin_client_path(@maria)
    assert_select "a[href=?]", admin_job_path(@job), /#{@job.number} · Gutter clean/
  end

  test "the automatic job setting" do
    patch admin_business_path(tab: "documents"), params: { business: { auto_create_jobs: "0" } }
    assert_not @business.reload.auto_create_jobs
    get admin_jobs_path
    assert_select "p", /don't become jobs on their own/
  end
end
