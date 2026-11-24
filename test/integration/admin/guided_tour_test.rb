require "test_helper"

# ACC-08: the tour is offered once to a new business's Owner, records where each person got to
# (never while support views as them), and comes back from Help.
class Admin::GuidedTourTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @membership = business_users(:one)
    sign_in users(:one)
  end

  def record(event, stop, format: :json) = patch(admin_tour_path(format:), params: { event:, stop: })

  test "a new business's Owner is offered the tour on Home until they take it or skip it" do
    @business.update!(onboarded_at: Time.current)
    get admin_root_path
    assert_select "#tour-offer", 0, "an existing business with its checklist finished isn't offered it"
    assert_select "#tour[role=dialog][aria-modal=false][aria-labelledby=tour-title]"
    assert_select "#help-menu ~ .menu a[href=?]", admin_root_path(tour: "start"), text: /Take the tour again/

    post admin_business_path, params: { business: { name: "Fresh Start Lawns", industry: "landscaping" } }
    membership = BusinessUser.find_by!(business: Business.find_by!(name: "Fresh Start Lawns"), user: users(:one))
    assert_equal "offered", membership.tour_status
    assert membership.tour_offered_at
    follow_redirect!
    assert_select "#tour-offer button[data-tour-start]", "Take a 2-minute tour"
    tour = JSON.parse(css_select("[data-controller=tour]").first["data-tour-tour-value"])
    assert_equal %w[home requests quotes schedule invoices settings], tour["stops"].map { _1["key"] }
    assert_equal "setup-services", tour.dig("next_step", "id") # #289: the four-step checklist

    patch admin_tour_path, params: { event: "end", stop: "offer" }
    assert_redirected_to admin_root_path
    assert_equal "No problem. The tour is in the Help menu whenever you want it.", flash[:notice]
    assert_equal %w[skipped offer], [ membership.reload.tour_status, membership.tour_stop ]
    follow_redirect!
    assert_select "#tour-offer", 0
  end

  # Owner decision of 2026-11-22.
  test "an existing business's Owner, its checklist unfinished, is offered it once on Home, recorded as a creator's" do
    @business.update!(onboarded_at: nil)
    assert_nil @membership.tour_status
    get admin_root_path
    assert_select "#tour-offer button[data-tour-start]", "Take a 2-minute tour"
    assert_select "#tour-offer form[action=?]", admin_tour_path
    assert_equal "offered", @membership.reload.tour_status
    offered_at = @membership.tour_offered_at
    assert offered_at
    get admin_root_path
    assert_equal offered_at, @membership.reload.tour_offered_at, "offered once"

    record "start", "home"
    record "step", "quotes"
    record "finish", "settings"
    assert_equal %w[finished settings], [ @membership.reload.tour_status, @membership.tour_stop ]
    assert @membership.tour_ended_at
    get admin_root_path
    assert_select "#tour-offer", 0, "not again after it's finished"
    assert_equal "finished", @membership.reload.tour_status
  end

  test "skipped, it isn't offered again; nor to someone who's had it in another business" do
    @business.update!(onboarded_at: nil)
    get admin_root_path
    patch admin_tour_path, params: { event: "end", stop: "offer" }
    assert_equal %w[skipped offer], [ @membership.reload.tour_status, @membership.tour_stop ]
    get admin_root_path
    assert_select "#tour-offer", 0

    other = Business.create!(name: "Second Yard", owner: users(:one))
    other.business_users.find_by!(user: users(:one)).update_columns(tour_status: nil, tour_offered_at: nil) # as if it predated the tour
    post switch_admin_business_path, params: { business: other.uid }
    get admin_root_path
    assert_select "#tour-offer", 0, "one offer per person"
    assert_nil other.business_users.find_by!(user: users(:one)).tour_status
  end

  # Every step of the checklist done. Payments aren't set up here, so the "Get paid online" step
  # must be absent: a gateway that isn't configured, whatever an earlier test left behind.
  def complete_setup!
    use_fake_payment_gateway(configured: false)
    as_business(@business) do
      CatalogItem.create!(name: "Weekly mowing", unit: "visit", unit_price: "45")
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5125550100" } ])
    end
    @business.update_columns(first_quote_sent_at: 1.day.ago, onboarded_at: nil)
    assert as_business(@business) { SetupChecklist.new(@business.reload, membership: @membership).complete? }, "the precondition: setup is complete"
  end

  test "an Owner whose setup is complete but not yet stamped isn't offered it" do
    complete_setup!
    get admin_root_path
    assert_select "#tour-offer", 0
    assert_nil @membership.reload.tour_status
  end

  test "hidden and then completed (never stamped onboarded), no offer" do
    complete_setup!
    @membership.update!(setup_hidden_at: 1.day.ago)
    get admin_root_path
    assert_nil @business.reload.onboarded_at, "a hidden checklist isn't stamped"
    assert_select "#tour-offer", 0
    assert_nil @membership.reload.tour_status
  end

  test "Turbo's hover prefetch shows the offer but doesn't record it; the real visit does" do
    @business.update!(onboarded_at: nil)
    get admin_root_path, headers: { "X-Sec-Purpose" => "prefetch" }
    assert_select "#tour-offer"
    assert_nil @membership.reload.tour_status
    get admin_root_path
    assert_equal "offered", @membership.reload.tour_status
  end

  test "only Owners are offered it, not Admins or Technicians (they have Help and My day)" do
    @business.update!(onboarded_at: nil)
    [ member_with_role(:admin), member_with_role(:technician) ].each do |user|
      sign_in user
      post switch_admin_business_path, params: { business: @business.uid }
      get admin_root_path
      follow_redirect! if response.redirect?
      assert_select "#tour-offer", 0
      assert_nil @business.business_users.find_by!(user:).tour_status
    end
  end

  test "support viewing as an existing business's Owner never gets the offer, and doesn't use it up" do
    business = businesses(:two)
    owner = business_users(:two)
    business.update!(onboarded_at: nil)
    sign_in_operator
    post ops_business_impersonation_path(business), params: { member: owner.uid, reason: "Ticket: walking through setup" }
    get admin_root_path
    assert_response :success
    assert_select "#tour-offer", 0
    assert_nil owner.reload.tour_status, "still to be offered to the Owner"
  end

  test "each move is recorded: started, the stop reached, then finished or ended where they stopped" do
    @membership.update!(tour_status: "offered")
    record "start", "home"
    assert_response :no_content
    record "step", "quotes"
    assert_equal %w[started quotes], [ @membership.reload.tour_status, @membership.tour_stop ]
    record "end", "quotes"
    assert_equal %w[skipped quotes], [ @membership.reload.tour_status, @membership.tour_stop ]

    record "start", "home" # again, from Help: stamped, the first run's outcome kept
    record "finish", "settings"
    assert_equal %w[skipped quotes], [ @membership.reload.tour_status, @membership.tour_stop ]
    assert_not_nil @membership.tour_replayed_at

    record "step", "billing"
    assert_response :unprocessable_content, "only this person's stops"
    record "restart", "home"
    assert_response :unprocessable_content, "only the tour's events"
  end

  # (owner, 2026-11-24) A reload isn't leaving: the unloading page reports the end, the reloaded
  # one that it resumed from it. The page ids come with each move.
  test "a run ended moments ago resumes from the reloaded page; the offer never does" do
    @membership.update!(tour_status: "offered")
    patch admin_tour_path(format: :json), params: { event: "start", stop: "home", page: "A" }
    patch admin_tour_path(format: :json), params: { event: "end", stop: "home", page: "A" }
    patch admin_tour_path(format: :json), params: { event: "resume", stop: "home", page: "B", from: "A" }
    assert_response :no_content
    assert_equal [ "started", "home", "A" ], [ @membership.reload.tour_status, @membership.tour_stop, @membership.tour_resumed_from ]

    @membership.update!(tour_status: "skipped", tour_stop: "offer", tour_ended_at: Time.current)
    patch admin_tour_path(format: :json), params: { event: "resume", stop: "offer", page: "B", from: "A" }
    assert_response :unprocessable_content, "only a stop resumes"
    assert_equal "skipped", @membership.reload.tour_status
  end

  # The tour points at these; a rebuilt Home or menu (#289) must keep them, or the tour loses its way.
  test "every element the tour points at is on its page" do
    use_fake_payment_gateway # so the payments step is there too
    @business.update!(onboarded_at: nil, phone: nil)
    get admin_root_path
    %w[checklist home requests quotes schedule invoices settings].each { assert_select "[data-tour~=#{_1}]", 1, _1 }
    %w[services client quote payments].each { assert_select "#setup-#{_1}", 1, _1 } # the last stop leads to a step by id (#289)
    assert_select "#setup-services a, #setup-services button" # and focuses its link or button
    assert_select "[data-tour~=checklist] button[data-tour-skip]", "Hide" # never Hide
    # My day's stops, for someone who lands there: office members reach it from Home, not the menu (#289).
    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_my_day_path
    %w[today coming_up my_day help].each { assert_select "[data-tour~=#{_1}]", 1, _1 }
  end

  test "the browser's JSON update passes forgery protection with the page's token, and not without" do
    ActionController::Base.allow_forgery_protection = true
    @membership.update!(tour_status: "offered")
    get admin_root_path
    token = css_select("meta[name=csrf-token]").first["content"]
    patch admin_tour_path, params: { event: "start", stop: "home" }.to_json,
                           headers: { "Content-Type" => "application/json", "Accept" => "application/json", "X-CSRF-Token" => token }
    assert_response :no_content
    assert_equal "started", @membership.reload.tour_status
    patch admin_tour_path, params: { event: "step", stop: "quotes" }.to_json, headers: { "Content-Type" => "application/json", "Accept" => "application/json" }
    assert_response :unprocessable_content
    assert_equal "home", @membership.reload.tour_stop
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  test "technicians take the short tour on My day, from the welcome or Help" do
    tech = User.create!(email: "crew@example.com", password: "password123", first_name: "Crew", confirmed_at: Time.current)
    BusinessUser.create!(business: @business, user: tech, role: "technician")
    sign_in tech
    get admin_my_day_path
    assert_select "button[data-tour-start]", "Show me around"
    assert_select "[data-tour=today]"
    assert_select "#help-menu ~ .menu a[href=?]", admin_my_day_path(tour: "start")
    tour = JSON.parse(css_select("[data-controller=tour]").first["data-tour-tour-value"])
    assert_equal %w[my_day coming_up help], tour["stops"].map { _1["key"] }
    assert_select "[data-tour=requests], [data-tour=settings]", 0, "no menu stops they can't use"

    record "start", "my_day"
    record "step", "requests"
    assert_response :unprocessable_content
    record "finish", "help", format: :html
    assert_redirected_to admin_my_day_path
    assert_equal "finished", BusinessUser.find_by!(user: tech).tour_status
  end

  test "support viewing as the member sees the tour but never marks it" do
    business = businesses(:two)
    owner = business_users(:two)
    owner.update!(tour_status: "offered")
    sign_in_operator
    post ops_business_impersonation_path(business), params: { member: owner.uid, reason: "Ticket: walking through setup" }
    get admin_root_path
    assert_select "[data-controller=tour][data-tour-record-value=false]"
    assert_select "#tour-offer button[data-tour-start]"
    assert_select "#tour-offer form", 0, "no Skip for support"

    record "start", "home"
    assert_response :forbidden
    patch admin_tour_path, params: { event: "end", stop: "offer" }
    assert_match "read-only", flash[:alert]
    patch ops_impersonation_path, params: { mode: "write", reason: "Fixing their settings with them" }
    record "end", "offer", format: :html
    assert_match "Support can't change this", flash[:alert]
    assert_equal "offered", owner.reload.tour_status
  end
end
