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
    get admin_client_path(as_business(@business) { @job.client })
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
    assert_select "#notes li", 0, "no notes yet, and the blank one for the form isn't listed"
    directions = css_select("a").find { _1.text.include?("Directions") }
    assert_match %r{\Ahttps://www\.google\.com/maps/dir/\?api=1&destination=12%20Elm%20St}, directions["href"]
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

    patch complete_admin_my_visit_path(@afternoon) # completing without starting is fine
    patch start_admin_my_visit_path(@tomorrow)
    patch complete_admin_my_visit_path(@tomorrow)
    assert_empty as_business(@business) { Notification.where(kind: "job_ready_to_invoice").to_a }, "the owner's visit is still open"
    office = member_with_role(:admin)
    as_business(@business) { @not_mine.cancel!(by: office) }
    ready = as_business(@business) { Notification.where(kind: "job_ready_to_invoice").to_a }
    assert_equal [ @owner ], ready.map(&:user), "cancelling the last open visit, with work done, means it's ready (not told: whoever cancelled)"
    assert_equal "Spring cleanup (#{@job.number}) is ready to invoice", ready.sole.title
    patch reopen_admin_my_visit_path(@tomorrow)
    patch complete_admin_my_visit_path(@tomorrow)
    assert_equal 2, as_business(@business) { Notification.where(kind: "job_ready_to_invoice", user: @owner).count }, "reopened, then done again: told again"
    patch complete_admin_my_visit_path(@tomorrow)
    assert_equal 2, as_business(@business) { Notification.where(kind: "job_ready_to_invoice", user: @owner).count }, "never twice for the same finish"
    assert_equal "in_progress", @job.reload.status, "staff complete the job"
  end

  test "reopening goes by the business's day, and not once the job is completed" do
    patch start_admin_my_visit_path(@morning)
    travel_to @business.local_time(@today, "23:58") do
      patch complete_admin_my_visit_path(@morning)
    end
    travel_to @business.local_time(@today + 1, "00:01") do
      patch reopen_admin_my_visit_path(@morning)
      assert_match "Only a visit completed today", flash[:alert], "a new day in New York, though not in UTC"
    end
    patch reopen_admin_my_visit_path(@morning)
    assert_equal "in_progress", @morning.reload.status
    patch complete_admin_my_visit_path(@morning)
    as_business(@business) { @job.reload.complete!(by: @owner) }
    get admin_my_visit_path(@morning)
    assert_select "form[action=?]", reopen_admin_my_visit_path(@morning), 0
  end

  test "a visit completed on an earlier day can't be reopened" do
    patch start_admin_my_visit_path(@morning)
    patch complete_admin_my_visit_path(@morning)
    Visit.unscoped.where(id: @morning.id).update_all(completed_at: 2.days.ago)
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
