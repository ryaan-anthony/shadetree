require "test_helper"

# PLT-14: each detail page's actions in their rank, on the shared page list's records
# (test/support/staff_pages.rb). The sweep over every page is design_system_test.rb.
class Admin::PageActionsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @pages = StaffPages.build(@business, @owner)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def visit_page(key) = get(StaffPages.find(@pages, key).path).tap { assert_response :success }
  def header_primaries = css_select(".page-head .btn-primary").reject { _1.ancestors("dialog").any? }.map { _1.text.squish }

  # Owner, 2026-11-22: the quote page's Primary is the next step. A cancelled job is reopened
  # (interim until the multi-job spec: a quote has one job).
  test "the quote page's Primary: Create job or Reopen job, then Create invoice, then none" do
    expected = { quote_sent: [], quote_changes: [], quote_declined: [], quote_expired: [], quote_archived: [],
                 quote_approved: [ "Create job" ], quote_job_cancelled: [ "Reopen job" ],
                 quote_with_job: [ "Create invoice" ], quote_billed: [] }
    actual = expected.keys.index_with do |key|
      visit_page(key)
      header_primaries
    end
    assert_equal expected, actual

    visit_page(:quote_job_cancelled)
    job = css_select(".page-head a.btn-secondary").find { _1.text.squish.start_with?("Job ") }
    form = css_select(".page-head form").find { _1.at_css("button.btn-primary")&.text&.squish == "Reopen job" }
    assert_equal "#{job["href"]}/reopen", form["action"]
    patch form["action"]
    assert_redirected_to job["href"]
    follow_redirect!
    assert_select ".page-head button", "Complete" # open again (nothing booked: Schedule visit is its Primary)

    visit_page(:quote_billed)
    assert_select ".page-head a.btn-secondary", /\AJob J-\d+\z/
    assert_select ".page-head a.btn-secondary", /\AInvoice INV-\d+\z/
  end

  test "the client page: New quote is the header's Primary; New job and New invoice are Secondary in Work" do
    visit_page(:client)
    assert_equal [ "New quote" ], header_primaries
    assert_select ".page-head .menu .menu-item", "Archive" # owner, 2026-11-22: clients keep Archive in the menu
    work = css_select("section.card").find { _1.at_css(".card-title")&.text == "Work" }
    assert_equal [ "New job", "New invoice" ], work.css(".card-head .btn").map { _1.text.squish }
    assert(work.css(".card-head .btn").all? { _1["class"].include?("btn-secondary") })

    visit_page(:client_archived)
    assert_empty header_primaries
    assert_select ".page-head .menu .menu-item", "Restore"
  end

  # Owner, 2026-11-22: with nothing booked, Schedule visit; once a visit is booked, Complete.
  test "the job page: Schedule visit, then Complete; Cancel job is Destructive" do
    visit_page(:job_unbooked)
    assert_equal [ "Schedule visit" ], header_primaries
    assert_select ".page-head button.btn-secondary", "Complete"

    visit_page(:job)
    assert_equal [ "Complete" ], header_primaries
    assert_select ".page-head button.btn-destructive", "Cancel job"
    assert_select "dialog#job-cancel input.btn-destructive-solid[value='Cancel job']"
    assert_select "dialog#job-cancel button.btn-tertiary", "Keep job"
  end

  test "a request whose client is archived shows Create quote disabled, and says why" do
    visit_page(:request)
    assert_select ".page-head button.btn-primary", "Create quote"
    assert_select ".page-head button.btn-destructive", "Archive"

    visit_page(:request_archived_client)
    assert_select ".page-head button", { text: "Create quote", count: 0 }
    assert_select ".page-head [aria-disabled=true][aria-describedby=request-client-archived]", "Create quote"
    assert_select "#request-client-archived", /is archived\. Restore them to quote this request\./
  end
end
