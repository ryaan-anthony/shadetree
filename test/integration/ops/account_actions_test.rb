require "test_helper"

# OPS-04: suspending and reactivating a business, and helping someone sign in.
class Ops::AccountActionsTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers
  include ActionMailer::TestHelper

  setup do
    @business = businesses(:two)
  end

  test "suspending needs a reason; members then see a contact-support page, clients see unavailable" do
    create_test_document_table
    link = as_business(@business) { ClientLink.issue!(create_test_document(@business)) }
    @business.update!(request_form_enabled: true)
    sign_in_operator
    post ops_business_suspension_path(@business), params: { reason: " " }
    assert_match "Give a reason", flash[:alert]
    assert_not @business.reload.suspended?

    post ops_business_suspension_path(@business), params: { reason: "Spam through client emails" }
    assert @business.reload.suspended?
    assert_not @business.active?
    entry = AuditEntry.find_by!(action: "business.suspended")
    assert_equal [ @business, "Spam through client emails" ], [ entry.business, entry.reason ]
    get ops_businesses_path(status: "suspended")
    assert_select "#businesses > li", 1
    assert_select "#business-#{@business.uid}", /Suspended/
    get ops_business_path(@business)
    assert_select "#account-actions", /Spam through client emails/

    assert_equal :unavailable, link.reload.status
    get client_link_path(link.token)
    assert_response :gone
    get public_request_path(@business.handle)
    assert_response :not_found
    sign_out :user

    sign_in users(:two)
    get admin_clients_path
    assert_response :forbidden
    assert_select "#business-suspended", /Test Business Two is suspended/
    assert_no_match "Spam", response.body, "the reason stays with operators"
    post switch_admin_business_path, params: { business: businesses(:one).uid }
    sign_out :user

    sign_in_operator
    delete ops_business_suspension_path(@business), params: { reason: "Owner confirmed it was a hacked account" }
    assert @business.reload.active?
    assert_nil @business.suspended_at
    assert AuditEntry.exists?(action: "business.reactivated", reason: "Owner confirmed it was a hacked account")
    assert_equal :active, link.reload.status
  end

  test "suspending needs a recent code, and closed businesses can't be suspended or reactivated" do
    sign_in_operator
    travel 6.minutes do
      post ops_business_suspension_path(@business), params: { reason: "x" }
      assert_redirected_to new_ops_two_factor_verification_path(recent: 1)
    end
    @business.suspend!(reason: "spam")
    @business.update_columns(active: false, suspended_at: nil) # then closed, as account deletion does (ACC-06)
    assert_raises(ArgumentError) { @business.reactivate! }
    post ops_business_suspension_path(@business), params: { reason: "x" }
    assert_match "Only an active business", flash[:alert]
    delete ops_business_suspension_path(@business), params: { reason: "x" }
    assert_match "isn't suspended", flash[:alert]
  end

  test "a suspended business closed by its owner deleting their account is no longer suspended" do
    owner = User.create!(email: "solo@example.com", password: "password123", first_name: "Solo", last_name: "Owner", confirmed_at: Time.current)
    business = Business.create!(name: "Solo Co", owner:)
    business.suspend!(reason: "spam")
    owner.delete_account!
    business.reload
    assert_equal [ false, nil ], [ business.active?, business.suspended_at ]
  end

  test "email queued for a business that's since suspended isn't sent" do
    message = as_business(@business) { EmailMessage.create!(to: "client@example.com", subject: "Hi", kind: EmailCatalog.kinds.first, status: "queued") }
    @business.suspend!(reason: "spam")
    ClientMailDeliveryJob.new("ClientMailer", "test", "deliver_now", args: [], params: { email_message_id: message.id }).perform_now
    assert_equal "failed", message.reload.status
  end

  test "operators resend confirmation, send a password reset and unlock an account, each audited" do
    sign_in_operator
    user = users(:unconfirmed)
    assert_enqueued_emails(1) { post confirmation_ops_user_path(user) }
    assert_redirected_to ops_users_path(email: user.email)
    post confirmation_ops_user_path(users(:two))
    assert_match "already confirmed", flash[:alert]

    assert_enqueued_emails(1) { post password_reset_ops_user_path(users(:two)) }
    users(:two).lock_access!(send_instructions: false)
    get ops_users_path(email: users(:two).email)
    assert_select "#user-actions-#{users(:two).id} button", /Unlock/
    post unlock_ops_user_path(users(:two))
    assert_not users(:two).reload.access_locked?
    post unlock_ops_user_path(users(:two))
    assert_match "isn't locked", flash[:alert]

    assert_equal %w[user.confirmation_resent user.password_reset_sent user.unlocked], AuditEntry.order(:id).where("action LIKE 'user.%'").pluck(:action)
    assert_equal users(:two), AuditEntry.find_by!(action: "user.unlocked").target_user
  end

  test "deleting a business: typed name and reason to schedule, the owner emailed; cancel or delete now" do
    sign_in_operator
    post ops_business_deletion_path(@business), params: { reason: "Owner asked", confirm_name: "Test Business" }
    assert_match "Type the business's name", flash[:alert]
    post ops_business_deletion_path(@business), params: { reason: "", confirm_name: @business.name }
    assert_match "Give a reason", flash[:alert]
    assert_nil @business.reload.deletion_due_at

    assert_enqueued_email_with BusinessDeletionMailer, :scheduled, params: { business: @business } do
      post ops_business_deletion_path(@business), params: { reason: "Owner asked by email", confirm_name: @business.name }
    end
    assert_in_delta 30.days.from_now, @business.reload.deletion_due_at, 5.seconds
    assert AuditEntry.exists?(action: "business.deletion_scheduled", reason: "Owner asked by email")
    get ops_business_path(@business)
    assert_select "#deletion", /Scheduled for deletion/

    delete ops_business_deletion_path(@business), params: { reason: "Changed their mind" }
    assert_nil @business.reload.deletion_due_at
    assert AuditEntry.exists?(action: "business.deletion_cancelled")

    post ops_business_deletion_path(@business), params: { reason: "Privacy request", confirm_name: @business.name }
    assert_enqueued_with(job: DeleteScheduledBusinessesJob, args: [ @business.id ]) do
      patch ops_business_deletion_path(@business), params: { reason: "Privacy request: now", confirm_name: @business.name }
    end
    assert_redirected_to ops_businesses_path
    perform_enqueued_jobs(only: DeleteScheduledBusinessesJob)
    assert_not Business.exists?(@business.id)
  end
end
