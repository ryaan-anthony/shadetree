require "test_helper"

# ACC-06, #317: a browser signed out from another device still sees public pages (client links,
# the marketing site), signed out; staff pages send it to sign in with a note.
class Users::EndedSessionPublicPagesTest < ActionDispatch::IntegrationTest
  PHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
  ENDED = "signed out from another device"

  setup do
    @user = users(:one)
    @business = businesses(:one)
    as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      @quote = Quote.start(client: maria).tap { _1.update!(title: "Spring cleanup") }
      @quote.update_column(:status, "sent")
      @invoice = Invoice.start(client: maria).tap { _1.update!(title: "Spring cleanup") }
      @invoice.update_columns(status: "sent", sent_at: Time.current)
      @quote_link = ClientLink.issue!(@quote)
      @invoice_link = @invoice.client_link!
    end
  end

  # A phone signed in, then signed out from a laptop.
  def ended_browser
    phone = open_session { _1.post user_session_path, params: { user: { email: @user.email, password: "password123" } }, headers: { "User-Agent" => PHONE } }
    laptop = open_session { _1.post user_session_path, params: { user: { email: @user.email, password: "password123" } } }
    @phone_session = @user.user_sessions.active.find_by!(user_agent: PHONE)
    laptop.delete user_browser_session_path(@phone_session)
    assert_not @phone_session.reload.active?
    phone
  end

  test "client links and the home page show, and the browser stays signed out" do
    { "quote link" => client_link_path(@quote_link.token), "invoice link" => client_link_path(@invoice_link.token), "home page" => root_path }.each do |name, path|
      phone = ended_browser
      phone.get path, headers: { "User-Agent" => PHONE }
      assert_equal 200, phone.response.status, "#{name} shows"
      assert_nil phone.flash[:alert]
      assert_not @phone_session.reload.active?, "#{name}: the session stays ended"
      assert_not @user.user_sessions.active.exists?(user_agent: PHONE), "#{name}: no new session"

      phone.get admin_root_path, headers: { "User-Agent" => PHONE }
      phone.assert_redirected_to new_user_session_path
      assert_no_match ENDED, phone.flash[:alert].to_s, "#{name}: already signed out, so the usual sign-in prompt"
    end
  end

  test "staff and account pages still send the browser to sign in with the note" do
    [ admin_root_path, edit_user_registration_path ].each do |path|
      phone = ended_browser
      phone.get path, headers: { "User-Agent" => PHONE }
      phone.assert_redirected_to new_user_session_path
      assert_match ENDED, phone.flash[:alert]
      assert_not @phone_session.reload.active?
    end
  end
end
