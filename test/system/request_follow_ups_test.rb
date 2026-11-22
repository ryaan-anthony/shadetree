require "application_system_test_case"

# CLI-07 and JOB-06: assigning a request, and following one up, with the keyboard alone (axe:
# test/system/accessibility_test.rb).
class RequestFollowUpsTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    # Open every day, 7 am to 9 pm, so today's follow-up has no warning whenever this runs.
    @business.update!(timezone: "America/New_York", weekly_hours: WeeklyHours::DAYS.to_h { [ _1.to_s, { "opens" => "07:00", "closes" => "21:00" } ] })
    @owner = users(:one)
    Tenancy.with_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @request_record = ServiceRequest.create!(client:, source: "phone", description: "Fence repair")
    end
  end

  def sign_in_as(user)
    visit new_user_session_path
    sign_in_with_form(user.email, "password123")
    assert_text user.full_name # in the menu, on Home or (for a technician) My day; a reload can drop the flash
  end

  # Keys typed wherever focus is, as a person would.
  def press(*keys) = page.driver.browser.action.send_keys(*keys).perform

  test "assign a request as a call, with the keyboard only" do
    sign_in_as @owner
    visit admin_service_request_path(@request_record)
    find("#follow-up a", text: "Assign").send_keys(:enter)
    assert_selector "h1", text: "Assign this request"
    find_field("Who follows it up").send_keys(:tab) # the only member is already chosen
    press(:right) # How: Site visit → Call
    assert_predicate find("#follow-up-kind-call"), :checked?
    find("#timing-anytime").send_keys(:left) # Time: Anytime → A start time
    assert_selector "#request_follow_up_start_time", visible: true
    find_field("Instructions for them").send_keys("Ask about the side gate")
    find("input[type=submit][value=Assign]").send_keys(:enter)
    assert_text "John Doe has it: call"
    assert_selector "#follow-up", text: /Call, .* · 9 am/
    assert_equal "Ask about the side gate", Tenancy.with_business(@business) { @request_record.reload.follow_up.instructions }
  end

  # JOB-06: a site photo goes up from the follow-up's page as on a visit, one at a time.
  test "add a site photo from the follow-up's page" do
    sign_in_as @owner
    Tenancy.with_business(@business) { RequestFollowUp.assign!(@request_record, { user: @owner, scheduled_on: @business.today }, by: @owner) }
    visit admin_my_request_path(@request_record)
    attach_file "choose-photos", file_fixture("logo.png").to_s, make_visible: true
    assert_selector "[role=status]", text: "Photo 1 added.", visible: :all
    assert_selector "#request-site-photos img[alt='Site photo 1']"
    assert_equal 1, Tenancy.with_business(@business) { @request_record.site_photos.count }
  end

  # JOB-06: from My day to the follow-up and Done, without a mouse.
  test "open a follow-up from My day and mark it done, with the keyboard only" do
    sign_in_as @owner
    Tenancy.with_business(@business) { RequestFollowUp.assign!(@request_record, { user: @owner, scheduled_on: @business.today, timing: "exact", start_time: "14:00" }, by: @owner) }
    visit admin_my_day_path
    find("#my-request-#{@request_record.uid} a").send_keys(:enter)
    assert_selector "h1", text: "Maria Lopez"
    find("#follow-up-action button", text: "Mark site visit done").send_keys(:enter)
    within("dialog[open]") { find("button", text: "Mark done").send_keys(:enter) }
    assert_text "Done."
    assert Tenancy.with_business(@business) { @request_record.reload.follow_up.done? }
  end

  # JOB-06: a technician the owner gave it to passes it back, with a note, without a mouse.
  test "pass a done follow-up back with a note, with the keyboard only" do
    tech = User.create!(email: "marcus@example.com", password: "password123", first_name: "Marcus", last_name: "Reyes", confirmed_at: Time.current)
    BusinessUser.create!(user: tech, business: @business, role: "technician")
    Tenancy.with_business(@business) do
      RequestFollowUp.assign!(@request_record, { user: tech, scheduled_on: @business.today }, by: @owner)
      @request_record.reload.follow_up.done!(by: tech)
    end
    sign_in_as tech
    visit admin_my_request_path(@request_record)
    find("#follow-up-action button", text: "Pass back to John Doe").send_keys(:enter)
    assert_selector "dialog[open] button[aria-label=Close]:focus" # the dialog's first control
    press(:tab)
    assert_selector "#pass-back-note:focus"
    press("Two posts rotten")
    press(:tab, :tab) # past "Not yet"
    assert_selector "dialog[open] input[type=submit][value='Pass it back']:focus"
    press(:enter)
    assert_text "Passed back to John Doe."
    Tenancy.with_business(@business) do
      assert_equal @owner, @request_record.reload.follow_up.user
      assert_equal "Two posts rotten", @request_record.notes.sole.body
    end
  end
end
