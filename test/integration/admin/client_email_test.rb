require "test_helper"

# NTF-01: bounce flags on clients, the test email, and recent emails.
class Admin::ClientEmailTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
    @maria = as_business(@business) do
      Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
    end
  end

  test "a bounced address is flagged on the client until staff send to it again" do
    as_business(@business) { EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce") }
    get admin_client_path(@maria)
    method = as_business(@business) { @maria.contact_methods.first }
    assert_select "#undeliverable-#{method.id}", /was refused by the mail server, so emails to it are/

    patch mark_deliverable_admin_client_path(@maria, contact_method_id: method.id)
    assert_redirected_to admin_client_path(@maria)
    as_business(@business) do
      assert_not EmailSuppression.suppressed?("maria@example.com")
      assert_not method.reload.undeliverable?
    end
  end

  test "an address that's already blocked is flagged when it's added to a client" do
    as_business(@business) do
      EmailSuppression.suppress!("old@example.com", reason: "hard_bounce")
      added = @maria.contact_methods.create!(kind: "email", value: "Old@Example.com")
      assert_equal "hard_bounce", added.undeliverable_reason
      assert added.undeliverable?
    end
  end

  test "another business's client or contact method can't be cleared, and its emails aren't shown" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "email", value: "theirs@example.com" } ])
      EmailSuppression.suppress!("theirs@example.com", reason: "hard_bounce")
      EmailMessage.create!(kind: "test_message", to: "theirs@example.com", subject: "Their quote", status: "bounced")
      client
    end
    method = as_business(businesses(:two)) { theirs.contact_methods.first }
    assert_not_found_across_businesses { patch mark_deliverable_admin_client_path(theirs, contact_method_id: method.id) }
    assert_not_found_across_businesses { patch mark_deliverable_admin_client_path(@maria, contact_method_id: method.id) }
    as_business(businesses(:two)) { assert EmailSuppression.suppressed?("theirs@example.com") }

    get admin_client_path(@maria)
    assert_no_match "Their quote", response.body
  end

  test "changing a flagged address clears the flag" do
    as_business(@business) do
      EmailSuppression.suppress!("maria@example.com", reason: "hard_bounce")
      method = @maria.contact_methods.first
      method.reload.update!(value: "maria.lopez@example.com")
      assert_not method.reload.undeliverable?
    end
  end

  # The 3-per-10-minutes rate limit uses the cache store, which is a null store in tests.
  test "send me a test email" do
    @business.update!(email: "office@example.com")
    perform_enqueued_jobs { post admin_test_email_path }
    assert_redirected_to edit_admin_business_path(tab: "branding")
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ users(:one).email ], mail.to
    assert_equal [ "office@example.com" ], mail.reply_to
    assert_equal "Test email from #{@business.name}", mail.subject
  end

  test "only owners and admins send test emails" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_test_email_path }
  end

  test "recent emails show on the client with their outcome" do
    as_business(@business) do
      quote = Quote.start(client: @maria).tap(&:save!) # #289: emails about this client's records
      EmailMessage.create!(kind: "quote_sent", to: "maria@example.com", subject: "Your quote", status: "bounced", related: quote)
    end
    get admin_client_path(@maria)
    assert_select "[id^=email-]", /Your quote.*Address refused/m
  end
end
