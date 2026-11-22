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
      @maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550123" } ],
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
    as_business(@business) { @request_record.photos.attach(io: file_fixture("logo.png").open, filename: "fence.png", content_type: "image/png") }
    get admin_my_request_path(@request_record)
    assert_response :success
    assert_select "h1", "Maria Lopez"
    assert_select "p", /Site visit for a request · Mon, Nov 23 · 2 pm · about 1 h/
    assert_select "a[href^='https://www.google.com/maps/dir/']", /Directions/
    assert_select "a[href='tel:+15125550123']", /Call/
    assert_select "a[href='sms:+15125550123']", /Text/
    assert_select "p", "(512) 555-0123"
    assert_select "p", /Side gate code 4417/
    assert_select "#request", /Fence leaning after the storm.*Before Christmas.*Measure the run/m
    assert_select "#request img[alt='Photo 1 from Maria Lopez']", 1, "the client's photos"
    assert_select "#notes li", /She mentioned a dog in the yard\..*John Doe/m
    assert_select "a[href=?]", admin_service_request_path(@request_record), 0, "no office links"
    assert_select "a[href=?]", admin_client_path(@maria), 0
  end

  test "Done tells whoever assigned it and keeps the request in progress; then it can be passed back with a note" do
    patch done_admin_my_request_path(@request_record)
    assert_redirected_to admin_my_request_path(@request_record)
    assert_equal "Done. John Doe knows.", flash[:notice]
    assert follow_up.done?
    assert_equal [ "in_progress", "done" ], as_business(@business) { [ @request_record.reload.status, @request_record.events.last.kind ] }
    notice = as_business(@business) { Notification.find_by!(user: @owner) }
    assert_equal [ "request_follow_up_done", "Marcus Reyes did the site visit for Maria Lopez" ], [ notice.kind, notice.title ]
    patch done_admin_my_request_path(@request_record)
    assert_equal "This is already marked done.", flash[:alert]

    get admin_my_request_path(@request_record)
    assert_select "button", /Pass back to John Doe/
    assert_select "form[action=?]", quote_admin_my_request_path(@request_record), 0, "a technician without the permission can't make quotes (QTE-07)"
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
    get admin_catalog_items_path
    assert_response :forbidden, "no prices"

    post admin_my_request_photos_path(@request_record), params: { photos: [ Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png") ] }, xhr: true
    photo = as_business(@business) { @request_record.site_photos.sole }
    patch done_admin_my_request_path(@request_record)
    sign_in users(:two)
    post switch_admin_business_path, params: { business: businesses(:two).uid }
    assert_not_found_across_businesses { get admin_my_request_path(@request_record) }
    assert_not_found_across_businesses { patch done_admin_my_request_path(@request_record) }
    assert_not_found_across_businesses { post admin_my_request_photos_path(@request_record), params: { photos: [ Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png") ] }, xhr: true }
    assert_not_found_across_businesses { delete admin_my_request_photo_path(@request_record, photo) }
    assert_not_found_across_businesses { post admin_my_request_notes_path(@request_record), params: { service_request_note: { body: "x" } } }
    assert_not_found_across_businesses { patch pass_back_admin_my_request_path(@request_record), params: { note: "x" } }
    as_business(@business) do
      assert_equal [ 1, 1, @tech ], [ @request_record.site_photos.count, @request_record.notes.count, @request_record.follow_up.user ], "nothing changed"
    end
  end

  test "the office sees Done on the request and in the inbox" do
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_service_request_path(@request_record)
    assert_select "#follow-up .badge", { text: "Done", count: 0 }
    get admin_service_requests_path(status: "in_progress")
    assert_select "#request-#{@request_record.uid} .badge", { text: "Done", count: 0 }

    as_business(@business) { follow_up.done!(by: @tech) }
    get admin_service_request_path(@request_record)
    assert_select "#follow-up .badge", "Done"
    get admin_service_requests_path(status: "in_progress")
    assert_select "#request-#{@request_record.uid} .badge", "Done"
  end

  test "office staff who have it can create the quote from it, and move or reassign it" do
    as_business(@business) { RequestFollowUp.assign!(@request_record, { user: @owner }, by: @tech) }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_request_path(@request_record)
    assert_select "a[href=?]", edit_admin_service_request_follow_up_path(@request_record), /Move or reassign/
    patch done_admin_my_request_path(@request_record)
    follow_redirect!
    assert_select "form[action=?] button", quote_admin_my_request_path(@request_record), /Create quote/ # QTE-07: through their follow-up
    assert_select "button", { text: /Pass back/, count: 1 }, "back to Marcus, who gave it to them"
  end

  test "passing back needs it done and still theirs; with nobody to pass to, the page says to ask the office" do
    patch pass_back_admin_my_request_path(@request_record)
    assert_equal "Mark it done first.", flash[:alert]
    assert_equal @tech, follow_up.user

    patch done_admin_my_request_path(@request_record)
    stale = follow_up
    admin = User.create!(email: "priya@example.com", password: "password123", first_name: "Priya", confirmed_at: Time.current)
    BusinessUser.create!(user: admin, business: @business, role: "admin")
    as_business(@business) { RequestFollowUp.assign!(@request_record, { user: admin }, by: @owner) }
    error = assert_raises(RequestFollowUp::NotOpen) { as_business(@business) { stale.pass_back!(by: @tech) } }
    assert_equal "This isn't yours to pass back any more.", error.message
    assert_equal admin, follow_up.user, "the office's move wins"

    as_business(@business) do
      RequestFollowUp.assign!(@request_record, { user: @tech }, by: admin)
      follow_up.done!(by: @tech)
      BusinessUser.find_by(user: admin).deactivate!
    end
    get admin_my_request_path(@request_record)
    assert_select ".banner-success", /Ask the office to reassign it\./
    assert_select "button", { text: /Pass back/, count: 0 }

    as_business(@business) { follow_up.update_columns(assigned_by_id: nil) }
    get admin_my_request_path(@request_record)
    assert_select ".banner-success", /Ask the office to reassign it\./
  end

  test "a deleted assigner can't be passed back to, and isn't told it's done" do
    admin = User.create!(email: "priya@example.com", password: "password123", first_name: "Priya", confirmed_at: Time.current)
    BusinessUser.create!(user: admin, business: @business, role: "admin")
    as_business(@business) do
      @request_record.follow_up.end!(by: admin)
      RequestFollowUp.assign!(@request_record.reload, { user: @tech, scheduled_on: Date.new(2026, 11, 23) }, by: admin)
    end
    assert admin.delete_account!
    patch done_admin_my_request_path(@request_record)
    assert_equal "Done.", flash[:notice]
    get admin_my_request_path(@request_record)
    assert_select ".banner-success", /Ask the office to reassign it\./
  end

  test "editing the details leaves it done; moving or handing it on makes it to do again" do
    patch done_admin_my_request_path(@request_record)
    as_business(@business) { RequestFollowUp.assign!(@request_record, { instructions: "Also the gate", duration_minutes: 90 }, by: @owner) }
    assert follow_up.done?
    as_business(@business) { RequestFollowUp.assign!(@request_record, { start_time: "15:00" }, by: @owner) }
    assert_not follow_up.done?
  end

  test "once it's archived, quoted or reassigned, its page isn't theirs" do
    as_business(@business) { @request_record.move_to!("archived", by: @owner) }
    get admin_my_request_path(@request_record)
    assert_response :not_found
    as_business(@business) do
      @request_record.move_to!("in_progress")
      RequestFollowUp.assign!(@request_record, { user: @tech, scheduled_on: Date.new(2026, 11, 23) }, by: @owner)
      @request_record.create_quote!(by: @owner)
    end
    get admin_my_request_path(@request_record)
    assert_response :not_found
    as_business(@business) { @request_record.update!(status: "in_progress") && RequestFollowUp.assign!(@request_record, { user: @tech, scheduled_on: Date.new(2026, 11, 23) }, by: @owner) }
    get admin_my_request_path(@request_record)
    assert_response :success
    as_business(@business) { RequestFollowUp.assign!(@request_record, { user: @owner }, by: @owner) }
    get admin_my_request_path(@request_record)
    assert_response :not_found
  end

  test "an office-only role that's given a request opens it from the request page and marks it done" do
    @business.update!(plan_overrides: { "features" => { "custom_roles" => true }, "limits" => { "team_members" => nil } })
    role = as_business(@business) { Role.create!(name: "Coordinator", permissions: %w[office]) }
    cora = User.create!(email: "cora@example.com", password: "password123", first_name: "Cora", confirmed_at: Time.current)
    BusinessUser.create!(user: cora, business: @business, role: "custom", role_id: role.id)
    as_business(@business) { RequestFollowUp.assign!(@request_record, { user: cora }, by: @owner) }
    sign_in cora
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    assert_response :forbidden, "no My day for this role"
    get admin_service_request_path(@request_record)
    assert_select "#follow-up a[href=?]", admin_my_request_path(@request_record), "Open your follow-up"
    patch done_admin_my_request_path(@request_record)
    assert follow_up.done?
  end
end
