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
    assert_equal [ "Next: Add your business details", "setup-details" ], owner_tour.next_step
    assert_equal admin_sample_quote_path, owner_tour.stops.find { _1.key == "quotes" }.link.last
  end

  test "Admins get the office stops without billing" do
    admin_tour = tour(member(:admin))
    assert_equal %w[home requests quotes schedule invoices settings], admin_tour.keys
    assert_no_match(/plan/, admin_tour.stops.map(&:text).join)
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
    assert_nil office_tour.stops.find { _1.key == "quotes" }.link, "the sample quote needs settings access"

    scheduler = as_business(@business) { Role.create!(name: "Scheduler", permissions: %w[schedule]) }
    assert_nil tour(member(:custom, role_id: scheduler.id)), "nothing on Home or My day to tour"
    assert_nil tour(member(:admin, active: false))
  end

  test "recording a run: start, step, finish or end; moves outside a run change nothing" do
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

    membership.record_tour!("start", "home") # again, from Help
    membership.record_tour!("finish", "settings")
    assert_equal %w[finished settings], [ membership.reload.tour_status, membership.tour_stop ]
  end

  private

  def admin_sample_quote_path = Rails.application.routes.url_helpers.admin_sample_quote_path
end
