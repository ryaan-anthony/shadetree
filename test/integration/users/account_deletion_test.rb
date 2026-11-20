require "test_helper"

# ACC-06: deleting your own account: password, the sole-owner rule, anonymization, and emails.
class Users::AccountDeletionTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  def delete_account(password: "password123") = delete(user_registration_path, params: { current_password: password })

  test "someone in no business deletes their account: everything personal goes, and they can't sign back in" do
    user = User.create!(email: "solo@example.com", password: "password123", first_name: "Sam", last_name: "Solo", confirmed_at: Time.current)
    sign_in user
    get edit_user_registration_path
    assert_select "#delete-account", /can't be undone/
    assert_select "#delete-account", { text: /A business only you own/, count: 0 }

    delete_account(password: "wrong")
    assert_match "didn't match", flash[:alert]
    assert_not user.reload.deleted?

    assert_enqueued_email_with AccountMailer, :deleted, params: { email: "solo@example.com", first_name: "Sam" } do
      delete_account
    end
    assert_redirected_to root_path
    user.reload
    assert user.deleted?
    assert_equal [ "deleted-user-#{user.id}@deleted.invalid", nil, nil ], [ user.email, user.first_name, user.last_name ]
    assert_equal "Former member", user.full_name
    assert_not user.valid_password?("password123")
    assert_empty user.user_sessions

    get admin_root_path
    assert_redirected_to new_user_session_path
    post user_session_path, params: { user: { email: "solo@example.com", password: "password123" } }
    assert_response :unprocessable_content
  end

  test "the only Owner of a business with other people can't delete until someone else is an Owner" do
    owner = users(:two) # business two, where user one is a technician
    sign_in owner
    get edit_user_registration_path
    assert_select "#delete-account", /only Owner of #{businesses(:two).name}/
    assert_select "#delete-account form", 0
    delete_account
    assert_match "only Owner", flash[:alert]
    assert_not owner.reload.deleted?

    business_users(:one_member_of_two).update!(role: "owner")
    delete_account
    assert owner.reload.deleted?
    assert businesses(:two).reload.active?, "the business carries on"
    assert_not business_users(:two).reload.active?
    assert business_users(:one_member_of_two).reload.active?
  end

  test "records in a business also block; an empty business only you own is closed" do
    owner = users(:one)
    as_business(businesses(:one)) { Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ]) }
    assert_equal [ businesses(:one) ], owner.businesses_blocking_deletion
    assert_not owner.delete_account!

    as_business(businesses(:one)) { Client.delete_all }
    business_users(:one_member_of_two).destroy! # leave business two out of it
    businesses(:one).update!(plan_overrides: { "features" => { "locations" => true } })
    branch = as_business(businesses(:one)) { Location.create!(name: "North yard", phone: "555-0177", email: "north@example.com", city: "Yonkers") }
    assert owner.reload.delete_account!
    assert_not businesses(:one).reload.active?
    as_business(businesses(:one)) do # CAT-07: the locations' details go too
      assert_equal [ nil, nil, nil ], branch.reload.values_at(:phone, :email, :city)
      assert_equal Location::PRIMARY_NAME, businesses(:one).primary_location.name
    end
  end

  test "past work shows Former member; the team can't reactivate a deleted account" do
    member = member_with_role("admin")
    quote = as_business(businesses(:one)) do
      client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.create!(client:, created_by: member)
    end
    assert member.delete_account!
    assert_equal "Former member", as_business(businesses(:one)) { quote.reload.created_by.full_name }

    sign_in users(:one)
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    get admin_team_path
    assert_select "li", /Former member.*deleted their account/m
    assert_select "button", { text: "Reactivate", count: 0 }
    membership = member.business_users.first
    patch reactivate_admin_member_path(membership)
    assert_match "deleted their Shadetree account", flash[:alert]
    assert_not membership.reload.active?
  end

  test "changing email confirms the new address and tells the old one" do
    user = users(:one)
    sign_in user
    assert_emails 2 do
      perform_enqueued_jobs do
        put user_registration_path, params: { user: { email: "new@example.com", current_password: "password123", first_name: user.first_name } }
      end
    end
    recipients = ActionMailer::Base.deliveries.last(2).flat_map(&:to)
    assert_includes recipients, "new@example.com"
    assert_includes recipients, user.email
    assert_equal user.email, user.reload.email, "the change waits for confirmation"
  end

  test "co-owners: the first can go, the last one then can't; a deactivated co-owner doesn't count" do
    business = businesses(:one)
    co = member_with_role("owner", business:)
    tech = member_with_role("technician", business:)
    assert users(:one).delete_account!, "another active Owner carries on"
    assert_equal [ business ], co.businesses_blocking_deletion
    assert_not co.delete_account!
    assert_not co.reload.delete_account!
    assert tech
  end

  test "an owner of an empty business who's also a member elsewhere: the empty one closes, the other carries on" do
    owner = users(:one) # sole owner of business one (empty), technician in business two
    assert_empty owner.businesses_blocking_deletion
    assert owner.delete_account!
    assert_not businesses(:one).reload.active?
    assert businesses(:two).reload.active?
    assert_not business_users(:one_member_of_two).reload.active?
  end

  test "closing an empty business cancels its Stripe subscription (BIL-04); a business without one calls nothing" do
    owner = users(:one)
    customer = with_stripe_customer(businesses(:one))
    live = stripe.add_subscription(customer:, plan: plans(:starter))
    ended = stripe.add_subscription(customer:, plan: plans(:starter), status: "canceled")
    assert_enqueued_with(job: CancelSubscriptionsJob, args: [ businesses(:one).id ]) { assert owner.delete_account! }
    perform_enqueued_jobs(only: CancelSubscriptionsJob)
    assert_equal "canceled", stripe.subscriptions[live][:status]
    assert_equal [ [ :cancel_subscription, live ] ], stripe.calls.select { _1.first == :cancel_subscription }
    assert_not_includes stripe.calls, [ :cancel_subscription, ended ]

    stripe.calls.clear
    assert_no_enqueued_jobs(only: CancelSubscriptionsJob) { users(:two).delete_account! }
  end

  test "closing an empty business revokes its pending invitations and clears its contact details" do
    owner = users(:one)
    business_users(:one_member_of_two).destroy!
    invitation = as_business(businesses(:one)) { Invitation.create!(email: "new@example.com", role: "admin", invited_by: owner) }
    businesses(:one).update_columns(email: "dana@example.com", phone: "5550100100")
    assert owner.delete_account!
    assert as_business(businesses(:one)) { invitation.reload.revoked_at }
    assert_equal [ nil, nil ], [ businesses(:one).reload.email, businesses(:one).phone ]
  end

  test "their name is gone from teammates' notifications, visit crew changes, accepted invitations and open visits" do
    business = businesses(:one)
    business.update!(plan_overrides: { "limits" => { "team_members" => 10 } }) # room for the invitation (BIL-03)
    member = member_with_role("technician", business:)
    member.update!(first_name: "Marcus", last_name: "Reyes")
    owner = users(:one)
    visit = as_business(business) do
      client = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      job = Job.create!(client:, title: "Mowing")
      job.visits.new(scheduled_on: business.today + 2, timing: "anytime", duration_minutes: 60, assignee_ids: [ member.id ]).tap { _1.schedule!(by: owner) }
    end
    as_business(business) do
      Notification.create!(business:, user: owner, actor: member, kind: "invitation_accepted", title: "Marcus Reyes joined as Technician", path: "/admin/team")
      Invitation.create!(email: "placeholder@example.com", role: "technician", invited_by: owner)
                .update_columns(email: member.email, accepted_at: Time.current, accepted_by_id: member.id)
    end

    assert member.delete_account!
    as_business(business) do
      assert_equal "Former member joined as Technician", Notification.find_by!(actor_id: member.id).title
      assert_equal "deleted-user-#{member.id}@deleted.invalid", Invitation.find_by!(accepted_by_id: member.id).email
      assert_empty visit.reload.assignees, "open visits show as unassigned"
    end
    texts = [ Notification, VisitEvent, Invitation ].flat_map { |model| as_business(business) { model.all.map { _1.attributes.to_json } } }.join
    assert_no_match(/Marcus|Reyes/, texts)
  end

  test "invitations they sent don't say Former member invited you" do
    businesses(:one).update!(plan_overrides: { "limits" => { "team_members" => 10 } }) # room for the invitation (BIL-03)
    inviter = member_with_role("admin")
    invitation = as_business(businesses(:one)) { Invitation.create!(email: "new@example.com", role: "technician", invited_by: inviter) }
    assert inviter.delete_account!
    mail = InvitationMailer.with(business_id: businesses(:one).id, invitation_id: invitation.id).invite
    assert_equal "Someone invited you to #{businesses(:one).name} on Shadetree", mail.subject
    assert_match "#{businesses(:one).name} invited you", mail.text_part.body.to_s
  end
end
