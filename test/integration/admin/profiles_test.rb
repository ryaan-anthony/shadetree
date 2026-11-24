require "test_helper"

# ACC-09: editing profiles: anyone their own, from the user menu; people who manage the team
# others' from Team (an Owner's only with manage_owners); changes by others are recorded and the
# member is told; support viewing as a member can't change them; never across businesses.
class Admin::ProfilesTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @business.update!(plan_overrides: { "limits" => { "team_members" => nil } })
    @owner = users(:one)
  end

  def as_member(user, business = @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def membership(user, business = @business) = business.business_users.find_by!(user:)
  def face = Rack::Test::UploadedFile.new(file_fixture("face.jpg"), "image/jpeg")
  def history(member) = Tenancy.with_business(member.business) { ProfileEvent.where(business_user: member).to_a }

  test "every role edits their own profile from the user menu, with a photo from their phone" do
    %i[owner admin technician].each do |role|
      user = member_with_role(role)
      as_member(user)
      get admin_my_day_path
      assert_select "a[href=?]", edit_admin_profile_path, /Your profile in Test Business/
      get edit_admin_profile_path
      assert_response :success
      assert_select "h1", "Your profile in #{@business.name}"
      assert_select "input[type=file][accept='image/png,image/jpeg,image/webp']"
      assert_select "label", "Add a photo"

      patch admin_profile_path, params: { business_user: { photo: face, title: "Crew lead", bio: "Hedges.", work_phone: "555-010-2200" } }
      assert_redirected_to edit_admin_profile_path
      member = membership(user)
      assert member.photo.attached?
      assert_equal [ "Crew lead", "Hedges.", "555-010-2200" ], [ member.title, member.bio, member.work_phone ]
      assert_empty history(member), "your own changes aren't a teammate's"
      sign_out user
    end
  end

  test "Replace and Remove, and errors on the page" do
    tech = member_with_role(:technician)
    as_member(tech)
    patch admin_profile_path, params: { business_user: { photo: face } }
    get edit_admin_profile_path
    assert_select "label", "Replace photo"
    assert_select "img.avatar-lg[alt=?]", tech.full_name

    small = Rack::Test::UploadedFile.new(file_fixture("rotated-6.jpg"), "image/jpeg")
    patch admin_profile_path, params: { business_user: { photo: small, title: "x" * 41 } }
    assert_response :unprocessable_content
    assert_select "#photo-error[role=alert]", /at least 128 pixels/
    assert_select "input[type=file][aria-describedby~=photo-error]"
    assert_select "#business_user_title[aria-invalid=true]"
    assert membership(tech).photo.attached?, "the photo there stays"

    patch admin_profile_path, params: { business_user: { remove_photo: "1" } }
    assert_not membership(tech).photo.attached?
  end

  test "a good photo with another field wrong is re-shown, not a crash, and isn't kept" do
    tech = member_with_role(:technician)
    as_member(tech)
    patch admin_profile_path, params: { business_user: { photo: face, work_phone: "12" } }
    assert_response :unprocessable_content
    assert_select "label", "Add a photo"
    assert_select "#business_user_work_phone[aria-invalid=true]"
    assert_not membership(tech).photo.attached?

    patch admin_profile_path, params: { business_user: { photo: face } }
    patch admin_profile_path, params: { business_user: { photo: face, work_phone: "12" } }
    assert_response :unprocessable_content, "replacing one too"
    assert_select "label", "Replace photo"
    assert_select "img.avatar-lg", 1, "the stored photo"
  end

  test "a deactivated member's profile change is recorded but they aren't notified" do
    tech = member_with_role(:technician)
    target = membership(tech)
    target.deactivate!
    as_member(@owner)
    patch admin_member_profile_path(target), params: { business_user: { title: "Seasonal" } }
    assert_equal 1, history(target).size
    assert_empty Tenancy.with_business(@business) { Notification.where(user: tech).to_a }
  end

  test "people who manage the team edit others' profiles; the change is recorded and the member told" do
    tech = member_with_role(:technician)
    admin = member_with_role(:admin)
    as_member(admin)
    get admin_team_path
    target = membership(tech)
    assert_select "#member-#{target.uid} a[href=?]", edit_admin_member_profile_path(target)
    assert_select "#member-#{membership(@owner).uid} a[href=?]", edit_admin_member_profile_path(membership(@owner)), count: 0

    get edit_admin_member_profile_path(target)
    assert_select "h1", "#{tech.full_name}'s profile"
    patch admin_member_profile_path(target), params: { business_user: { photo: face, title: "Mower whisperer", bio: "" } }
    assert_redirected_to admin_team_path

    event = history(target).sole
    assert_equal [ admin, %w[photo title] ], [ event.user, event.changed_fields ]
    notice = Tenancy.with_business(@business) { Notification.where(user: tech).sole }
    assert_equal "profile_changed", notice.kind
    assert_equal "#{admin.full_name} changed your photo and title in #{@business.name}", notice.title
    assert_equal edit_admin_profile_path, notice.path

    get admin_team_path
    assert_select "#member-#{target.uid} details", /#{admin.full_name} changed the photo and title/
    patch admin_member_profile_path(target), params: { business_user: { title: "Mower whisperer" } }
    assert_equal 1, history(target).size, "saving nothing new records nothing"
  end

  test "only manage_owners edits an Owner's profile; technicians can't edit others' or open Team" do
    admin = member_with_role(:admin)
    as_member(admin)
    owner = membership(@owner)
    get edit_admin_member_profile_path(owner)
    assert_response :forbidden
    patch admin_member_profile_path(owner), params: { business_user: { title: "Boss" } }
    assert_response :forbidden
    assert_nil owner.reload.title
    sign_out admin

    tech = member_with_role(:technician)
    as_member(tech)
    other = membership(member_with_role(:technician))
    get edit_admin_member_profile_path(other)
    assert_response :forbidden
    patch admin_member_profile_path(other), params: { business_user: { title: "Nope" } }
    assert_response :forbidden
    get admin_team_path
    assert_response :forbidden
    sign_out tech

    second_owner = member_with_role(:owner)
    as_member(second_owner)
    patch admin_member_profile_path(owner), params: { business_user: { title: "Founder" } }
    assert_equal "Founder", owner.reload.title
  end

  test "another business's members aren't found" do
    as_member(@owner)
    other = business_users(:two)
    assert_not_found_across_businesses { get edit_admin_member_profile_path(other) }
    assert_not_found_across_businesses { patch admin_member_profile_path(other), params: { business_user: { title: "Hacked" } } }
    assert_nil other.reload.title
  end

  test "a deleted account's profile can't be edited" do
    gone = member_with_role(:technician)
    target = membership(gone)
    gone.update_columns(deleted_at: Time.current)
    as_member(@owner)
    get edit_admin_member_profile_path(target)
    assert_redirected_to admin_team_path
  end

  test "support viewing as a member sees profiles but can't change them in either mode" do
    sign_in_operator
    post ops_business_impersonation_path(businesses(:two)), params: { member: business_users(:two).uid, reason: "Ticket: photo won't upload" }
    get edit_admin_profile_path
    assert_response :success
    patch admin_profile_path, params: { business_user: { title: "Support was here" } }
    assert_match "read-only", flash[:alert]
    patch ops_impersonation_path, params: { mode: "write", reason: "Helping with their profile" }
    patch admin_profile_path, params: { business_user: { title: "Support was here" } }
    assert_match "can't change this", flash[:alert]
    assert_nil business_users(:two).reload.title
  end
end
