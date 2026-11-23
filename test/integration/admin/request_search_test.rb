require "test_helper"

# PLT-19 (owner, 2026-11-23): the request list searches as you type, like the other lists: by
# client or by what they asked for, within the tab and assignee shown, and never across businesses.
class Admin::RequestSearchTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @sam = Client.create!(display_name: "Sam Okafor", contact_methods_attributes: [ { kind: "email", value: "sam@example.com" } ])
      @fence = ServiceRequest.create!(client: @maria, source: "phone", description: "Fence repair")
      @gutters = ServiceRequest.create!(client: @sam, source: "phone", description: "Gutter guards")
      @archived = ServiceRequest.create!(client: @sam, source: "phone", description: "Fence staining").tap { _1.update!(status: "archived") }
    end
    as_business(businesses(:two)) do
      other = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @theirs = ServiceRequest.create!(client: other, source: "phone", description: "Fence repair")
    end
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def shown = css_select("li[id^=request-]").map { _1["id"].delete_prefix("request-") }

  test "the list has a search box that searches as you type, with no Search button" do
    get admin_service_requests_path
    assert_select "form#request-filters[method=post][action=?][data-controller=search-form][data-turbo-frame=request_results]", search_admin_service_requests_path do
      assert_select "input[type=search][name=q][data-action*='search-form#queue']"
      assert_select "input[type=hidden][name=status][value=new]"
      assert_select "button, input[type=submit]", 0
    end
    assert_select "p#request_results_status[role=status]", 1 # outside the frame
    assert_select "turbo-frame#request_results[target=_top] [data-results-summary]", "2 requests"
  end

  test "by client or by what they asked for, within the tab, and only this business's" do
    post search_admin_service_requests_path, params: { q: "fence", status: "new" }, headers: { "Turbo-Frame" => "request_results" }
    assert_response :success
    assert_equal [ @fence.uid ], shown, "not the archived one (another tab), nor another business's"
    assert_select "turbo-frame#request_results"
    assert_select "h1", 0, "just the frame"

    post search_admin_service_requests_path, params: { q: "sam@example.com", status: "new" }, headers: { "Turbo-Frame" => "request_results" }
    assert_equal [ @gutters.uid ], shown

    post search_admin_service_requests_path, params: { q: "fence", status: "archived" }, headers: { "Turbo-Frame" => "request_results" }
    assert_equal [ @archived.uid ], shown

    post search_admin_service_requests_path, params: { q: "nothing like it", status: "new" }, headers: { "Turbo-Frame" => "request_results" }
    assert_select ".empty-title", "No requests match"
    assert_not_includes response.body, @theirs.uid
  end

  test "the search keeps the assignee filter" do
    as_business(@business) { RequestFollowUp.assign!(@gutters, { user: users(:one), scheduled_on: @business.today }, by: users(:one)) }
    post search_admin_service_requests_path, params: { q: "sam", status: "in_progress", assignee: "mine" }, headers: { "Turbo-Frame" => "request_results" }
    assert_equal [ @gutters.uid ], shown
    post search_admin_service_requests_path, params: { q: "sam", status: "in_progress", assignee: "unassigned" }, headers: { "Turbo-Frame" => "request_results" }
    assert_empty shown
  end

  test "without JavaScript, Enter posts the form and gets the whole page back" do
    post search_admin_service_requests_path, params: { q: "gutter", status: "new" }
    assert_response :success
    assert_select "h1", "Requests"
    assert_select "input#q[value=gutter]"
    assert_equal [ @gutters.uid ], shown
  end

  test "technicians can't search requests" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { post search_admin_service_requests_path, params: { q: "fence" } }
  end
end
