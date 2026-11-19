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
    assert owner.reload.delete_account!
    assert_not businesses(:one).reload.active?
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
end
