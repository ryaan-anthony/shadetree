require "test_helper"

# JOB-06: a request the signed-in member is following up, on their day: what they see, Done,
# passing it back, and that nothing else opens.
class Admin::MyRequestsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    as_business(@business) do
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                              properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", access_notes: "Side gate code 4417", billing: true } ])
      @request_record = ServiceRequest.create!(client: @maria, property: @maria.properties.first, source: "phone", description: "Fence leaning after the storm",
                                               timing: "Before Christmas")
      @request_record.notes.create!(user: @owner, body: "She mentioned a dog in the yard.")
      RequestFollowUp.assign!(@request_record, { user: @tech, scheduled_on: Date.new(2026, 11, 23), timing: "exact", start_time: "14:00",
                                                 instructions: "Measure the run" }, by: @owner)
      other = Client.create!(display_name: "Sam Ortiz", contact_methods_attributes: [ { kind: "phone", value: "5550100101" } ])
      @not_mine = ServiceRequest.create!(client: other, source: "phone", description: "Gutters")
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def follow_up = as_business(@business) { @request_record.reload.follow_up }

  test "the assignee sees who, where, how to reach them, what was asked, the instructions and the office's notes" do
    get admin_my_request_path(@request_record)
    assert_response :success
    assert_select "h1", "Maria Lopez"
    assert_select "p", /Site visit for a request · Mon, Nov 23 · 2 pm · about 1 h/
    assert_select "a[href^='https://www.google.com/maps/dir/']", /Directions/
    assert_select "a[href='tel:5550100100']", /Call/
    assert_select "a[href='sms:5550100100']", /Text/
    assert_select "p", "(555) 010-0100"
    assert_select "p", /Side gate code 4417/
    assert_select "#request", /Fence leaning after the storm.*Before Christmas.*Measure the run/m
    assert_select "a[href=?]", admin_service_request_path(@request_record), 0, "no office links"
    assert_select "a[href=?]", admin_client_path(@maria), 0
  end

  test "Done tells whoever assigned it and keeps the request in progress; then it can be passed back with a note" do
    patch done_admin_my_request_path(@request_record)
    assert_redirected_to admin_my_request_path(@request_record)
    assert_equal "Done. John knows.", flash[:notice]
    assert follow_up.done?
    assert_equal [ "in_progress", "done" ], as_business(@business) { [ @request_record.reload.status, @request_record.events.last.kind ] }
    notice = as_business(@business) { Notification.find_by!(user: @owner) }
    assert_equal [ "request_follow_up_done", "Done: Marcus Reyes site visit for Maria Lopez" ], [ notice.kind, notice.title ]
    patch done_admin_my_request_path(@request_record)
    assert_equal "This is already marked done.", flash[:alert]

    get admin_my_request_path(@request_record)
    assert_select "button", /Pass back to John Doe/
    assert_select "form[action=?]", quote_admin_service_request_path(@request_record), 0, "a technician can't make quotes (QTE-07)"
    patch pass_back_admin_my_request_path(@request_record), params: { note: "About 40 m; two posts rotten." }
    assert_redirected_to admin_my_day_path
    assert_equal [ @owner, false, Date.new(2026, 11, 23), "anytime" ], [ follow_up.user, follow_up.done?, follow_up.scheduled_on, follow_up.timing ]
    as_business(@business) do
      assert_equal "About 40 m; two posts rotten.", @request_record.notes.last.body
      assert_equal [ "passed_back", @tech.id, @owner.id ], @request_record.events.last.then { [ _1.kind, _1.data["from_user_id"], _1.data["to_user_id"] ] }
      assert_equal [ "Passed back to you: site visit for Maria Lopez", "About 40 m; two posts rotten." ], Notification.where(user: @owner).order(:id).last.then { [ _1.title, _1.body ] }
    end

    get admin_my_request_path(@request_record)
    assert_response :not_found, "not theirs any more"
  end

  test "only their own requests, only while theirs; nothing in the office opens" do
    get admin_my_request_path(@not_mine)
    assert_response :not_found
    patch done_admin_my_request_path(@not_mine)
    assert_response :not_found
    get admin_service_request_path(@request_record)
    assert_response :forbidden
    get admin_service_requests_path
    assert_response :forbidden
    get admin_client_path(@maria)
    assert_response :forbidden

    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get admin_my_request_path(@request_record) }
    assert_not_found_across_businesses { patch done_admin_my_request_path(@request_record) }
  end

  test "office staff who have it can create the quote from it, and move or reassign it" do
    as_business(@business) { RequestFollowUp.assign!(@request_record, { user: @owner }, by: @tech) }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_request_path(@request_record)
    assert_select "a[href=?]", edit_admin_service_request_follow_up_path(@request_record), /Move or reassign/
    patch done_admin_my_request_path(@request_record)
    follow_redirect!
    assert_select "form[action=?] button", quote_admin_service_request_path(@request_record), /Create quote/
    assert_select "button", { text: /Pass back/, count: 1 }, "back to Marcus, who gave it to them"
  end
end
