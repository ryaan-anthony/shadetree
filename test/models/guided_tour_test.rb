require "test_helper"

# ACC-08: the tour fits the role: stops for what the role can't use are left out.
class GuidedTourTest < ActiveSupport::TestCase
  setup do
    @business = businesses(:one)
    @business.update!(onboarded_at: nil, phone: nil)
  end

  def member(role, **attributes)
    user = User.create!(email: "#{role}-#{SecureRandom.hex(3)}@example.com", password: "password123", first_name: role.to_s.capitalize, confirmed_at: Time.current)
    BusinessUser.create!(business: @business, user:, role:, **attributes)
  end

  def tour(membership) = as_business(@business) { GuidedTour.for(membership, checklist: SetupChecklist.new(@business, membership:)).tap { _1&.stops } }

  test "Owners get six office stops, starting at the checklist, the plan in Settings, ending at the first unfinished step" do
    owner_tour = tour(business_users(:one))
    assert_equal :office, owner_tour.page
    assert_equal %w[home requests quotes schedule invoices settings], owner_tour.keys
    assert_equal %w[checklist home], owner_tour.stops.first.targets
    assert_match "checklist", owner_tour.stops.first.text
    assert_match "your plan", owner_tour.stops.last.text
    assert_equal [ "Next: Add your services and prices", "setup-services" ], owner_tour.next_step # #289: the four-step checklist
    assert_equal admin_sample_quote_path, owner_tour.stops.find { _1.key == "quotes" }.link.last
  end

  test "Admins get the office stops without billing" do
    admin_tour = tour(member(:admin))
    assert_equal %w[home requests quotes schedule invoices settings], admin_tour.keys
    assert_no_match(/plan/, admin_tour.stops.map(&:text).join)
  end

  test "the last stop skips checklist steps the person can't act on (getting paid online is the Owner's)" do
    step = ->(key, title) { SetupChecklist::Step.new(key:, title:, text: "", done: false, optional: false, action: "") }
    checklist = Struct.new(:required) { def visible? = true }.new([ step.("payments", "Get paid online"), step.("client", "Add a client") ])
    assert_equal [ "Next: Get paid online", "setup-payments" ], GuidedTour.for(business_users(:one), checklist:).next_step
    assert_equal [ "Next: Add a client", "setup-client" ], GuidedTour.for(member(:admin), checklist:).next_step
  end

  test "with the checklist done, Home points at the menu and the tour ends without a next step" do
    @business.update!(onboarded_at: Time.current)
    owner_tour = tour(business_users(:one))
    assert_equal %w[home], owner_tour.stops.first.targets
    assert_nil owner_tour.next_step
  end

  test "technicians get the short My day tour; custom roles only what they can use" do
    tech_tour = tour(member(:technician))
    assert_equal :field, tech_tour.page
    assert_equal %w[my_day coming_up help], tech_tour.keys

    office_only = as_business(@business) { Role.create!(name: "Office help", permissions: %w[office]) }
    office_tour = tour(member(:custom, role_id: office_only.id))
    assert_equal %w[home requests quotes invoices], office_tour.keys
    assert_equal %w[home], office_tour.stops.first.targets, "Home shows them no checklist"
    assert_no_match(/checklist/, office_tour.stops.first.text)
    assert_nil office_tour.next_step
    assert_nil office_tour.stops.find { _1.key == "quotes" }.link, "the sample quote needs settings access"

    scheduler = as_business(@business) { Role.create!(name: "Scheduler", permissions: %w[schedule]) }
    assert_nil tour(member(:custom, role_id: scheduler.id)), "nothing on Home or My day to tour"
    assert_nil tour(member(:admin, active: false))
  end

  test "recording the first run: start, step, finish or end; moves outside a run change nothing" do
    membership = member(:admin)
    membership.record_tour!("step", "quotes")
    membership.record_tour!("finish", "settings")
    assert_nil membership.reload.tour_status

    membership.record_tour!("start", "home")
    membership.record_tour!("step", "quotes")
    assert_equal %w[started quotes], [ membership.tour_status, membership.tour_stop ]
    membership.record_tour!("end", "quotes")
    assert_equal %w[skipped quotes], [ membership.tour_status, membership.tour_stop ]
    assert membership.tour_ended_at

    ended_at = membership.tour_ended_at
    membership.record_tour!("start", "home") # again, from Help: the first run's outcome stays
    membership.record_tour!("step", "schedule")
    membership.record_tour!("finish", "settings")
    assert_equal [ "skipped", "quotes", ended_at ], [ membership.reload.tour_status, membership.tour_stop, membership.tour_ended_at ]
    assert membership.tour_replayed_at

    finished = member(:admin)
    finished.record_tour!("start", "home")
    finished.record_tour!("finish", "settings")
    finished.record_tour!("start", "home") # a half-finished replay doesn't turn it back to started
    finished.record_tour!("step", "quotes")
    assert_equal %w[finished settings], [ finished.reload.tour_status, finished.tour_stop ]
  end

  # (owner, 2026-11-24) A reload isn't leaving. The unloading page A reports its end; the reloaded
  # page B reports resume from A. Either can reach the server first.
  test "a reload resumes the run whichever report comes first, and it can still finish" do
    late_end = member(:admin)
    late_end.record_tour!("start", "home", page: "A")
    late_end.record_tour!("step", "quotes", page: "A")
    late_end.record_tour!("resume", "quotes", page: "B", from: "A")
    late_end.record_tour!("end", "quotes", page: "A") # A's own end, late: ignored
    assert_equal [ "started", "quotes", nil ], [ late_end.reload.tour_status, late_end.tour_stop, late_end.tour_ended_at ]
    late_end.record_tour!("step", "schedule", page: "B")
    late_end.record_tour!("finish", "settings", page: "B")
    assert_equal %w[finished settings], [ late_end.reload.tour_status, late_end.tour_stop ]

    end_first = member(:admin)
    end_first.record_tour!("start", "home", page: "A")
    end_first.record_tour!("step", "quotes", page: "A")
    end_first.record_tour!("end", "quotes", page: "A")
    end_first.record_tour!("resume", "quotes", page: "B", from: "A")
    assert_equal [ "started", "quotes", nil, "A" ], [ end_first.reload.tour_status, end_first.tour_stop, end_first.tour_ended_at, end_first.tour_resumed_from ]
    end_first.record_tour!("finish", "settings", page: "B")
    assert_equal %w[finished settings], [ end_first.reload.tour_status, end_first.tour_stop ]

    left = member(:admin) # B, resumed, is then left for good: its end counts
    left.record_tour!("start", "home", page: "A")
    left.record_tour!("resume", "home", page: "B", from: "A")
    left.record_tour!("end", "home", page: "B")
    assert_equal %w[skipped home], [ left.reload.tour_status, left.tour_stop ]
  end

  test "a resume never reopens a skipped offer, another stop, an old end or the first run under a replay" do
    membership = member(:admin)
    membership.offer_tour!
    membership.record_tour!("end", "offer", page: "A")
    membership.record_tour!("resume", "offer", page: "B", from: "A")
    assert_equal %w[skipped offer], [ membership.reload.tour_status, membership.tour_stop ]

    membership.update!(tour_status: "skipped", tour_stop: "quotes", tour_ended_at: Time.current)
    membership.record_tour!("resume", "requests", page: "B", from: "A")
    membership.record_tour!("resume", "quotes", page: "B") # from no page
    assert_equal "skipped", membership.reload.tour_status
    membership.update!(tour_ended_at: 3.minutes.ago)
    membership.record_tour!("resume", "quotes", page: "B", from: "A")
    assert_equal "skipped", membership.reload.tour_status, "not long after"
    membership.update!(tour_ended_at: 1.minute.ago, tour_replayed_at: Time.current)
    membership.record_tour!("resume", "quotes", page: "B", from: "A")
    assert_equal "skipped", membership.reload.tour_status, "a replay's reload keeps the first run's outcome"
  end

  private

  def admin_sample_quote_path = Rails.application.routes.url_helpers.admin_sample_quote_path
end
