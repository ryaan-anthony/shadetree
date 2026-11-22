require "test_helper"

# JOB-06: requests a member is following up, on My day among their visits; notes and photos from
# site; what the office sees of them.
class Admin::MyDayFollowUpsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.utc(2026, 11, 23, 15) # a Monday, 10 am in New York
    @business = businesses(:one)
    @business.update!(timezone: "America/New_York")
    @owner = users(:one)
    @tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: @tech, business: @business, role: "technician")
    today = Date.new(2026, 11, 23)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ],
                             properties_attributes: [ { address_line1: "12 Elm St", city: "Austin", billing: true } ])
      job = Job.create!(client: maria, property: maria.properties.first, title: "Spring cleanup")
      book = ->(at) { job.visits.new(scheduled_on: today, timing: "exact", start_time: at, duration_minutes: 60, assignee_ids: [ @tech.id ]).tap { _1.schedule!(by: @owner) } }
      @one_pm, @three_pm = book.("13:00"), book.("15:00")
      phones = (1..).each
      request = ->(name, **when_) do
        client = Client.create!(display_name: name, contact_methods_attributes: [ { kind: "phone", value: format("51255501%02d", phones.next) } ])
        ServiceRequest.create!(client:, source: "phone", description: "Fence for #{name}").tap { RequestFollowUp.assign!(_1, { user: @tech, **when_ }, by: @owner) }
      end
      @two_pm = request.("Sam Ortiz", scheduled_on: today, timing: "exact", start_time: "14:00")
      @anytime = request.("Ana Diaz", scheduled_on: today, kind: "call")
      @overdue = request.("Lee Park", scheduled_on: today - 3)
      @next_week = request.("Kim Chu", scheduled_on: today + 7, timing: "window", start_time: "09:00", window_end_time: "11:00")
      @too_far = request.("Far Away", scheduled_on: today + 20)
      other = Client.create!(display_name: "Not Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      @not_mine = ServiceRequest.create!(client: other, source: "phone", description: "Nope").tap { RequestFollowUp.assign!(_1, { user: @owner, scheduled_on: today }, by: @owner) }
    end
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def photo = Rack::Test::UploadedFile.new(file_fixture("logo.png"), "image/png", original_filename: "fence.png")

  test "follow-ups sit among the visits: timed in time order, anytime after, overdue with earlier, the next two weeks after" do
    get admin_my_day_path
    today = css_select("li[id^=my-]").map { _1["id"] }.first(4) # Today comes first
    assert_equal [ "my-visit-#{@one_pm.uid}", "my-request-#{@two_pm.uid}", "my-visit-#{@three_pm.uid}", "my-request-#{@anytime.uid}" ], today
    assert_select "#my-request-#{@two_pm.uid}", /2 pm.*Site visit for a request.*Sam Ortiz.*Fence for Sam Ortiz/m
    assert_select "#my-request-#{@anytime.uid}", /Anytime.*Call for a request.*Ana Diaz/m
    assert_select ".card", /Still open from earlier.*Lee Park/m
    assert_select ".card", /Coming up.*Kim Chu/m
    assert_select "#my-request-#{@too_far.uid}", 0
    assert_select "#my-request-#{@not_mine.uid}", 0
  end

  test "a done follow-up stays, marked, until it's quoted or passed back" do
    patch done_admin_my_request_path(@two_pm)
    get admin_my_day_path
    assert_select "#my-request-#{@two_pm.uid} .badge", "Done"
  end

  test "notes and photos from site, on their own request only; the office sees them" do
    post admin_my_request_notes_path(@two_pm), params: { service_request_note: { body: "Two posts rotten" } }
    assert_redirected_to admin_my_request_path(@two_pm, anchor: "notes")
    post admin_my_request_photos_path(@two_pm), params: { photos: [ photo ] }, xhr: true
    assert_response :created
    assert_select "img[alt='Site photo 1']"
    post admin_my_request_photos_path(@not_mine), params: { photos: [ photo ] }, xhr: true
    assert_response :not_found
    post admin_my_request_notes_path(@not_mine), params: { service_request_note: { body: "x" } }
    assert_response :not_found
    get admin_my_request_path(@two_pm)
    assert_select "#notes li", /Two posts rotten.*Marcus Reyes/m
    assert_select "#request-site-photos li", 1

    attachment = as_business(@business) { @two_pm.site_photos.sole }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_service_request_path(@two_pm)
    assert_select "#site-photos img[alt='Site photo 1 of 1']"
    assert_select "#notes li", /Two posts rotten/
    delete admin_my_request_photo_path(@two_pm, attachment)
    assert_response :not_found, "only the person following it up manages its site photos"

    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    delete admin_my_request_photo_path(@two_pm, attachment)
    assert_redirected_to admin_my_request_path(@two_pm, anchor: "photos")
  end

  # My day's statements on a fresh sign-in, so each count is taken the same way.
  def my_day_queries
    sign_out @tech
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_my_day_path }
    assert_response :success
    queries
  end

  test "My day's queries don't grow with what's on it" do
    before = my_day_queries
    as_business(@business) do
      client = Client.create!(display_name: "Busy", contact_methods_attributes: [ { kind: "phone", value: "5125550199" } ])
      job = Job.create!(client:, title: "Busy week")
      20.times do |n|
        on = Date.new(2026, 11, 23) + (n % 5)
        job.visits.new(scheduled_on: on, timing: "exact", start_time: "08:00", duration_minutes: 30, assignee_ids: [ @tech.id ]).schedule!(by: @owner)
        RequestFollowUp.assign!(ServiceRequest.create!(client:, source: "phone", description: "More #{n}"), { user: @tech, scheduled_on: on }, by: @owner)
      end
    end
    assert_equal before, my_day_queries
  end

  test "a new assignee can't remove the site photos an earlier one took, only their own" do
    post admin_my_request_photos_path(@two_pm), params: { photos: [ photo ] }, xhr: true
    marcus_photo = as_business(@business) { @two_pm.site_photos.sole }
    priya = User.create!(email: "priya@example.com", password: "password123", first_name: "Priya", confirmed_at: Time.current)
    BusinessUser.create!(user: priya, business: @business, role: "technician")
    as_business(@business) { RequestFollowUp.assign!(@two_pm, { user: priya }, by: @owner) }
    sign_in priya
    post switch_admin_business_path, params: { business: @business.uid }

    get admin_my_request_path(@two_pm)
    assert_select "#request-site-photos li", 1
    assert_select "button[aria-label='Remove site photo 1']", 0
    delete admin_my_request_photo_path(@two_pm, marcus_photo)
    assert_response :not_found
    assert as_business(@business) { @two_pm.site_photos.exists?(marcus_photo.id) }

    post admin_my_request_photos_path(@two_pm), params: { photos: [ photo ] }, xhr: true
    priya_photo = as_business(@business) { @two_pm.site_photos.where.not(id: marcus_photo.id).sole }
    get admin_my_request_path(@two_pm)
    assert_select "button[aria-label='Remove site photo 1']", 0
    assert_select "button[aria-label='Remove site photo 2']", 1
    delete admin_my_request_photo_path(@two_pm, priya_photo)
    assert_redirected_to admin_my_request_path(@two_pm, anchor: "photos")
  end

  # The follow-up page's statements on a fresh sign-in, so each count is taken the same way.
  def follow_up_page_queries
    sign_out @tech
    sign_in @tech
    post switch_admin_business_path, params: { business: @business.uid }
    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get admin_my_request_path(@two_pm) }
    assert_response :success
    queries
  end

  test "the follow-up page's queries don't grow with its notes and photos" do
    add = lambda do
      as_business(@business) do
        @two_pm.photos.attach(io: file_fixture("logo.png").open, filename: "client.png", content_type: "image/png")
        @two_pm.add_site_photo_from(photo, by: @tech)
        @two_pm.notes.create!(user: @owner, body: "From the office")
        @two_pm.notes.create!(user: @tech, body: "From site")
      end
    end
    add.()
    before = follow_up_page_queries
    3.times { add.() }
    assert_equal before, follow_up_page_queries
  end

  test "a done one from an earlier day waits under Still open from earlier until it's passed back" do
    patch done_admin_my_request_path(@two_pm)
    travel 1.day
    get admin_my_day_path
    assert_select ".card", /Still open from earlier.*Sam Ortiz/m
    patch pass_back_admin_my_request_path(@two_pm)
    get admin_my_day_path
    assert_select "#my-request-#{@two_pm.uid}", 0
  end

  test "work at a location in another zone is placed on that location's day and labelled with its zone" do
    travel_to Time.utc(2026, 11, 23, 5, 30) # 00:30 Monday in New York; 7:30 pm Sunday in Honolulu
    @business.update!(plan_overrides: { "features" => { "locations" => true } })
    island = as_business(@business) do
      honolulu = Location.create!(name: "Island yard", timezone: "Pacific/Honolulu")
      client = Client.create!(display_name: "Kai Akana", contact_methods_attributes: [ { kind: "phone", value: "8085550123" } ])
      ServiceRequest.create!(client:, source: "phone", description: "Lanai", location: honolulu)
                    .tap { RequestFollowUp.assign!(_1, { user: @tech, scheduled_on: Date.new(2026, 11, 22), timing: "exact", start_time: "20:00" }, by: @owner) }
    end
    get admin_my_day_path
    today = css_select("li[id^=my-]").map { _1["id"] }
    assert_equal "my-request-#{island.uid}", today.first, "still Sunday there, so today, not overdue"
    assert_select "#my-request-#{island.uid}", /8 pm HST/
    assert_select "#my-visit-#{@one_pm.uid}", /1 pm/
    assert_select "#my-visit-#{@one_pm.uid}", { text: /EST/, count: 0 }, "the business's own zone isn't repeated"
  end
end
