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
    get admin_root_path
    assert_select "#tour-offer", 0, "existing businesses aren't offered it"
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
    assert_equal "setup-details", tour.dig("next_step", "id")

    patch admin_tour_path, params: { event: "end", stop: "offer" }
    assert_redirected_to admin_root_path
    assert_equal "No problem. The tour is in the Help menu whenever you want it.", flash[:notice]
    assert_equal %w[skipped offer], [ membership.reload.tour_status, membership.tour_stop ]
    follow_redirect!
    assert_select "#tour-offer", 0
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

  # The tour points at these; a rebuilt Home or menu (#289) must keep them, or the tour loses its way.
  test "every element the tour points at is on its page" do
    @business.update!(onboarded_at: nil, phone: nil)
    get admin_root_path
    %w[checklist home requests quotes schedule invoices settings].each { assert_select "[data-tour~=#{_1}]", 1, _1 }
    %w[details services branding client quote].each { assert_select "#setup-#{_1}", 1, _1 } # the last stop leads to a step by id
    assert_select "#setup-details a", "Add details" # and focuses its button
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
