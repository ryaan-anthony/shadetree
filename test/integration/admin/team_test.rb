require "test_helper"

# ACC-03: invitations and membership management.
class Admin::TeamTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:one)
    @owner = users(:one)
  end

  def as_member(user, business = @business)
    sign_in user
    post switch_admin_business_path, params: { business: business.uid }
  end

  def invite(email, role: "technician")
    post admin_invitations_path, params: { invitation: { email:, role: } }
  end

  def invitation_for(email) = Tenancy.across_businesses(reason: "test") { Invitation.find_by!(email:) }

  test "the team page needs manage_team" do
    assert_permission_matrix(owner: true, admin: true, technician: false) { get admin_team_path }
  end

  test "it lists members, invitations and deactivated people" do
    as_member(@owner)
    invite("new@example.com")
    gone = member_with_role(:technician)
    @business.business_users.find_by!(user: gone).deactivate!

    get admin_team_path
    assert_select "#member-#{business_users(:one).uid}", /#{@owner.email}/
    assert_select "[id^=invitation-]", /new@example.com/
    assert_select ".card", /Deactivated.*#{gone.full_name}/m
  end

  test "inviting sends an email naming the business and inviter" do
    as_member(@owner)
    assert_enqueued_emails(1) { invite("Crew@Example.com") }
    invitation = invitation_for("crew@example.com")
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "crew@example.com" ], mail.to
    assert_match @business.name, mail.subject
    assert_match @owner.full_name, mail.subject
    assert_match "/invitations/#{invitation.token}", mail.body.encoded
  end

  test "members and pending invitations can't be invited twice" do
    as_member(@owner)
    invite(@owner.email.upcase)
    assert_match "already belongs to a member", flash[:alert]

    invite("twice@example.com")
    invite("twice@example.com")
    assert_match "already has a pending invitation", flash[:alert]
  end

  test "admins can't invite owners; unconfirmed people can't invite at all" do
    as_member(member_with_role(:admin))
    invite("boss@example.com", role: "owner")
    assert_equal "Only owners can invite owners.", flash[:alert]

    unconfirmed = users(:unconfirmed)
    BusinessUser.create!(user: unconfirmed, business: @business, role: "admin")
    sign_out :user
    as_member(unconfirmed)
    assert_no_enqueued_emails { invite("x@example.com") }
    assert_match "Confirm your email", flash[:alert]
  end

  test "resend extends the expiry; revoke kills the link" do
    as_member(@owner)
    invite("late@example.com")
    invitation = invitation_for("late@example.com")
    travel 6.days do
      post resend_admin_invitation_path(invitation)
      assert_in_delta 7.days.from_now, invitation.reload.expires_at, 5.seconds
    end
    patch revoke_admin_invitation_path(invitation)
    sign_out :user
    get invitation_path(invitation.token)
    assert_response :gone
  end

  test "a new person accepts, sets a password and lands in the business, confirmed" do
    as_member(@owner)
    invite("newbie@example.com")
    invitation = invitation_for("newbie@example.com")
    sign_out :user

    get invitation_path(invitation.token)
    assert_select "input#user_email[value='newbie@example.com'][disabled]"
    post sign_up_invitation_path(invitation.token), params: { user: { first_name: "Nia", password: "a long password", terms_of_service: "1" } }
    assert_redirected_to admin_root_path

    user = User.find_by!(email: "newbie@example.com")
    assert user.confirmed?
    assert_equal "technician", @business.business_users.find_by!(user:).role
    assert_equal @business.id, user.last_business_id
    assert invitation.reload.accepted_at
    follow_redirect!
    assert_select ".biz-switch", /#{@business.name}/
  end

  test "an existing account signs in first and then accepts" do
    as_member(@owner)
    invite(users(:two).email)
    invitation = invitation_for(users(:two).email)
    sign_out :user

    get invitation_path(invitation.token)
    assert_select "a", "Sign in to accept"
    post user_session_path, params: { user: { email: users(:two).email, password: "password123" } }
    assert_redirected_to invitation_path(invitation.token)
    post accept_invitation_path(invitation.token)
    assert_redirected_to admin_root_path
    assert @business.business_users.active.exists?(user: users(:two))
  end

  test "signed in as someone else is explained, and accepting does nothing" do
    as_member(@owner)
    invite("someone@example.com")
    invitation = invitation_for("someone@example.com")
    sign_out :user
    sign_in users(:two)

    get invitation_path(invitation.token)
    assert_select ".banner", /for someone@example.com.*signed in as #{users(:two).email}/m
    post accept_invitation_path(invitation.token)
    assert_nil invitation.reload.accepted_at
  end

  test "expired and used invitations are refused" do
    as_member(@owner)
    invite("slow@example.com")
    invitation = invitation_for("slow@example.com")
    sign_out :user
    travel 8.days do
      get invitation_path(invitation.token)
      assert_response :gone
      assert_select "p", /expired/
    end
    get invitation_path("1" * Invitation::TOKEN_LENGTH)
    assert_response :not_found
  end

  test "deactivating ends access on the next request; reactivating restores the role" do
    tech = member_with_role(:admin)
    membership = @business.business_users.find_by!(user: tech)
    tech_session = open_session
    tech_session.post user_session_path, params: { user: { email: tech.email, password: "password123" } }
    tech_session.post switch_admin_business_path, params: { business: @business.uid }
    tech_session.get admin_team_path
    assert_equal 200, tech_session.response.status

    as_member(@owner)
    patch deactivate_admin_member_path(membership)
    assert_not membership.reload.active?

    tech_session.get admin_team_path
    assert_equal new_admin_business_url, tech_session.response.location

    patch reactivate_admin_member_path(membership)
    assert_equal [ true, "admin" ], [ membership.reload.active?, membership.role ]
  end

  test "role changes follow the rules" do
    admin = member_with_role(:admin)
    tech = @business.business_users.find_by!(user: member_with_role(:technician))
    as_member(admin)
    patch admin_member_path(tech), params: { member: { role: "admin" } }
    assert_equal "admin", tech.reload.role
    patch admin_member_path(business_users(:one)), params: { member: { role: "technician" } }
    assert_equal "Only owners can change owners.", flash[:alert]
    patch deactivate_admin_member_path(business_users(:one))
    assert business_users(:one).reload.active?
  end

  test "the last owner can't be demoted, and you can't deactivate yourself" do
    as_member(@owner)
    patch admin_member_path(business_users(:one)), params: { member: { role: "admin" } }
    assert_match "last owner", flash[:alert]
    patch deactivate_admin_member_path(business_users(:one))
    assert_equal "You can't deactivate yourself.", flash[:alert]
  end

  test "another business's members and invitations are not found" do
    as_member(@owner)
    other_invite = as_business(businesses(:two)) { Invitation.create!(email: "x@two.test", role: "technician", invited_by: users(:two)) }
    assert_not_found_across_businesses { patch deactivate_admin_member_path(business_users(:two)) }
    assert_not_found_across_businesses { patch revoke_admin_invitation_path(other_invite) }
    assert_nil other_invite.reload.revoked_at
  end

  test "last active is recorded" do
    as_member(@owner)
    get admin_root_path
    assert business_users(:one).reload.last_active_at > 1.minute.ago
  end
end
