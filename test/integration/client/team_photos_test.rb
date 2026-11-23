require "test_helper"

# ACC-09: what clients may see of the team. Off by default: nothing. On: only the people a card
# or message about their visit shows (assigned, active, with a first name), with photo, first
# name and title; a photo loads only through the visit's link, checked on every request, then
# a storage URL that expires in 5 minutes. Another member's photo can't be fetched.
class Client::TeamPhotosTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "limits" => { "team_members" => nil } }, show_team_profiles: true)
    @marcus = member_with_role(:technician)
    @marcus.update!(first_name: "Marcus", last_name: "Reyes")
    @dee = member_with_role(:technician)
    @other = member_with_role(:technician) # on the team, not on the visit
    [ @marcus, @dee, @other ].each { membership(_1).update!(photo: face, title: "Lead technician", work_phone: "555-010-2200") }
    as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      @job = Job.create!(client:, title: "Spring cleanup")
      @visit = @job.visits.new(scheduled_on: @business.today + 1, timing: "anytime", duration_minutes: 60, assignee_ids: [ @marcus.id, @dee.id ])
      @visit.schedule!(by: users(:one), notify_client: false)
      @token = @visit.client_link!.token
    end
    @previous_cards = Visit.client_team_cards
    Visit.client_team_cards = [ ->(visit) { visit.assignments.map(&:user_id) } ] # stands in for JOB-12's card: everyone on it
  end

  teardown { Visit.client_team_cards = @previous_cards }

  def face = Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg")
  def membership(user) = @business.business_users.find_by!(user:)
  def photo(user, token: @token) = get(client_team_photo_path(token, membership(user).uid))

  test "an assigned member's photo redirects to a storage URL that expires in 5 minutes" do
    photo(@marcus)
    assert_response :redirect
    location = response.location
    assert_match %r{/rails/active_storage/disk/}, location
    assert_match(/max-age=240, private/, response.headers["Cache-Control"])
    get location
    assert_response :success
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 256, 256 ], [ image.width, image.height ], "the square from the middle, not the original"
    travel(6.minutes) { get location }
    assert_response :not_found, "the storage URL has expired"
  end

  test "another member's photo can't be fetched through this visit's link" do
    photo(@other)
    assert_response :not_found
    photo(@marcus, token: "x" * ClientLink::TOKEN_LENGTH)
    assert_response :not_found
  end

  test "only while the setting is on, the member is active, has a first name and a card shows them" do
    @business.update!(show_team_profiles: false)
    photo(@marcus)
    assert_response :not_found
    @business.update!(show_team_profiles: true)

    membership(@dee).deactivate!
    photo(@dee)
    assert_response :not_found

    @marcus.update_columns(first_name: nil)
    photo(@marcus)
    assert_response :not_found
    @marcus.update_columns(first_name: "Marcus")

    Visit.client_team_cards = []
    photo(@marcus)
    assert_response :not_found
  end

  test "a revoked link cuts the photo off, and another business's members are never found" do
    as_business(@business) { ClientLink.active.find_by!(linkable: @visit).revoke!(by: users(:one)) }
    photo(@marcus)
    assert_response :gone

    other = business_users(:two)
    other.update!(photo: face)
    as_business(@business) { @token = @visit.reload.client_link!.token }
    get client_team_photo_path(@token, other.uid)
    assert_response :not_found
  end

  test "a quote or invoice link can't load team photos" do
    quote = as_business(@business) { Quote.create!(client: @job.client, title: "Mowing") }
    link = as_business(@business) { ClientLink.issue!(quote) }
    get client_team_photo_path(link.token, membership(@marcus).uid)
    assert_response :not_found
  end

  test "the client card shows photo, first name and title, and nothing else" do
    @dee.update!(first_name: "Dee", last_name: "Okafor")
    team = as_business(@business) { @visit.reload.client_team_shown }
    assert_equal %w[Dee Marcus], team.map(&:client_first_name)
    html = ApplicationController.render(partial: "client/team/member", locals: { member: team.last, client_link: ClientLink.find_by_token(@token) })
    fragment = Nokogiri::HTML.fragment(html)
    assert_equal "", fragment.at("img")["alt"], "the name is beside it"
    assert_equal client_team_photo_path(@token, membership(@marcus).uid), fragment.at("img")["src"]
    assert_equal "Marcus Lead technician", fragment.text.squish
    [ "Reyes", @marcus.email, "555-010-2200" ].each { assert_not_includes html, _1 }

    membership(@marcus).update!(remove_photo: "1")
    html = ApplicationController.render(partial: "client/team/member", locals: { member: membership(@marcus).reload, client_link: ClientLink.find_by_token(@token) })
    assert_equal "M", Nokogiri::HTML.fragment(html).at(".avatar").text, "the first initial only"
  end

  test "with the setting off (the default), clients are shown nobody" do
    assert_not Business.new.show_team_profiles?
    @business.update!(show_team_profiles: false)
    assert_empty as_business(@business) { @visit.reload.client_team }
  end

  test "the phone clients see is the work phone, else the location's, else none" do
    member = membership(@marcus)
    @business.update!(phone: "(555) 380-4410")
    assert_equal "555-010-2200", member.client_phone(as_business(@business) { @visit.contact })
    member.update!(work_phone: nil)
    assert_equal "(555) 380-4410", member.client_phone(as_business(@business) { @visit.contact })
  end
end
