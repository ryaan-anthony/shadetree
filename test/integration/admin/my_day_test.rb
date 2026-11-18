require "test_helper"

# JOB-04: a technician's day: only their visits, everything needed on site, start and complete.
class Admin::MyDayTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @tech = member_with_role(:technician)
    @owner = users(:one)
    @today = @business.today
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "(555) 010-0100" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true, access_notes: "Gate code 4417" } ])
      @job = Job.create!(client: maria, property: maria.properties.first, title: "Spring cleanup", instructions: "Bag the leaves")
      @job.line_items.create!(name: "Leaf cleanup", quantity: 2, unit: "hour", unit_price: "90")
      book = ->(on, at, crew, **more) { @job.visits.new(scheduled_on: on, timing: "exact", start_time: at, duration_minutes: 60, assignee_ids: crew, **more).tap { _1.schedule!(by: @owner) } }
      @afternoon = book.(@today, "14:00", [ @tech.id ])
      @morning = book.(@today, "08:00", [ @tech.id ], instructions: "Front beds first")
      @tomorrow = book.(@today + 1, "09:00", [ @tech.id ])
      @not_mine = book.(@today, "10:00", [ @owner.id ])
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "technicians land on My day and see only their visits, today in time order, then what's coming" do
    get admin_root_path
    assert_redirected_to admin_my_day_path
    follow_redirect!
    assert_select "nav a[href=?]", admin_my_day_path, /My day/
    assert_select "nav a[href=?]", admin_root_path, 0
    ids = css_select("li[id^=my-visit-]").map { _1["id"].delete_prefix("my-visit-") }
    assert_equal [ @morning.uid, @afternoon.uid, @tomorrow.uid ], ids
    assert_select "#my-visit-#{@morning.uid}", /8 am.*Maria Lopez.*12 Elm St, Austin.*Spring cleanup/m
  end

  test "another member's visit, the job and the office pages are out of reach" do
    get admin_my_visit_path(@not_mine)
    assert_response :not_found
    patch start_admin_my_visit_path(@not_mine)
    assert_response :not_found
    get admin_job_path(@job)
    assert_response :forbidden
    get admin_client_path(@job.client)
    assert_response :forbidden
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs").visits.new(scheduled_on: @today).tap { _1.schedule!(by: nil) }
    end
    assert_not_found_across_businesses { get admin_my_visit_path(theirs) }
  end

  test "a visit shows where, how to get in, who to call and what to do, without prices unless allowed" do
    get admin_my_visit_path(@morning)
    assert_response :success
    assert_select "a[href^='https://www.google.com/maps/search/?api=1&query=12%20Elm%20St']", /Directions/
    assert_select "main", /Gate code 4417/
    assert_select "a[href='tel:5550100100']", /Call/
    assert_select "a[href='sms:5550100100']", /Text/
    assert_select "main", /Bag the leaves.*This visit:.*Front beds first/m
    assert_select "#visit-work", /Leaf cleanup.*2 hour/m
    assert_select "#visit-work .money", 0
    @business.update!(technicians_see_prices: true)
    get admin_my_visit_path(@morning)
    assert_select "#visit-work .money", /\$90.00/
  end

  test "start, complete, reopen the same day, and the office hears when the job's work is done" do
    patch start_admin_my_visit_path(@morning)
    assert_equal [ "in_progress", "in_progress" ], [ @morning.reload.status, @job.reload.status ]
    assert @morning.started_at
    patch complete_admin_my_visit_path(@morning)
    assert_equal "completed", @morning.reload.status
    get admin_my_visit_path(@morning)
    assert_select "form[action=?]", reopen_admin_my_visit_path(@morning)
    patch reopen_admin_my_visit_path(@morning)
    assert_equal "in_progress", @morning.reload.status
    patch complete_admin_my_visit_path(@morning)

    [ @afternoon, @tomorrow ].each { patch complete_admin_my_visit_path(_1) }
    assert_match "This visit is scheduled", flash[:alert], "a visit is started before it's completed"
    [ @afternoon, @tomorrow ].each do |visit|
      patch start_admin_my_visit_path(visit)
      patch complete_admin_my_visit_path(visit)
    end
    assert_empty as_business(@business) { Notification.where(kind: "job_ready_to_invoice").to_a }, "the owner's visit is still open"
    as_business(@business) { @not_mine.cancel!(by: @owner) }
    patch reopen_admin_my_visit_path(@tomorrow)
    patch complete_admin_my_visit_path(@tomorrow)
    ready = as_business(@business) { Notification.where(kind: "job_ready_to_invoice").to_a }
    assert_equal [ @owner ], ready.map(&:user)
    assert_equal "Spring cleanup (#{@job.number}) is ready to invoice", ready.sole.title
    assert_equal "in_progress", @job.reload.status, "staff complete the job"
  end

  test "a visit completed on an earlier day can't be reopened" do
    patch start_admin_my_visit_path(@morning)
    patch complete_admin_my_visit_path(@morning)
    @morning.update_columns(completed_at: 2.days.ago)
    patch reopen_admin_my_visit_path(@morning)
    assert_match "Only a visit completed today", flash[:alert]
  end

  test "notes from the crew, seen by the office" do
    post admin_my_visit_notes_path(@morning), params: { visit_note: { body: "Side gate was locked; came back at 2" } }
    assert_redirected_to admin_my_visit_path(@morning, anchor: "notes")
    post admin_my_visit_notes_path(@morning), params: { visit_note: { body: " " } }
    assert_match "Write something first", flash[:alert]
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_job_path(@job)
    assert_select "#visit-#{@morning.uid}", /Side gate was locked; came back at 2.*#{@tech.full_name}/m
  end

  test "Owners and Admins can open their own My day" do
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_root_path
    assert_response :success
    get admin_my_day_path
    assert_select "li[id^=my-visit-]", 1
    get admin_my_visit_path(@not_mine)
    assert_select "#visit-work .money", /\$90.00/, "the office sees prices anyway"
  end
end
