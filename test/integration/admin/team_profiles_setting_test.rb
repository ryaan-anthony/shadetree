require "test_helper"

# ACC-09: "Show team profiles to clients" in Settings → Messages, off by default, linked from the
# Team page; only people with business_settings change it. The export and account deletion say
# what happens to profiles.
class Admin::TeamProfilesSettingTest < ActionDispatch::IntegrationTest
  setup { @business = businesses(:one) }

  def as_member(user)
    sign_in user
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def turn_on = patch(admin_business_path(tab: "team_profiles"), params: { business: { show_team_profiles: "1" } })

  test "off by default; an Owner turns it on and off in Settings → Messages" do
    assert_not @business.show_team_profiles?
    as_member(users(:one))
    get admin_message_templates_path
    assert_select "#team-profiles input[type=checkbox][name='business[show_team_profiles]']:not([checked])"
    assert_select "#team-profiles label", /Show team profiles to clients/

    turn_on
    assert_redirected_to admin_message_templates_path(anchor: "team-profiles")
    assert @business.reload.show_team_profiles?
    patch admin_business_path(tab: "team_profiles"), params: { business: { show_team_profiles: "0" } }
    assert_not @business.reload.show_team_profiles?
  end

  test "only business_settings changes it" do
    assert_permission_matrix(owner: true, admin: true, technician: false) { turn_on }
  end

  test "the Team page says whether clients see profiles and links to the setting" do
    as_member(users(:one))
    get admin_team_path
    assert_select "#team-profiles-setting", /Clients don't see team profiles/
    assert_select "#team-profiles-setting a[href=?]", admin_message_templates_path(anchor: "team-profiles")
    @business.update!(show_team_profiles: true)
    get admin_team_path
    assert_select "#team-profiles-setting", /Clients see team profiles/
  end

  test "the full export leaves team profiles out, and its README says so" do
    assert_includes DataExport::Archive::NOT_INCLUDED.first, "team profiles"
  end

  test "the account deletion page says profiles go and sent emails can't be recalled" do
    as_member(member_with_role(:technician))
    get edit_user_registration_path
    assert_select "#delete-account li", /profile photo, title, bio and work phone are removed.*can't be recalled/
  end
end
