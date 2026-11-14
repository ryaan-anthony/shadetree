require "test_helper"

class ConfirmedSenderTest < ActionDispatch::IntegrationTest
  class SendController < Admin::BaseController
    before_action :require_confirmed_sender
    def create = head(:ok)
  end

  setup do
    Rails.application.routes.disable_clear_and_finalize = true
    Rails.application.routes.draw { post "/test_send", to: "confirmed_sender_test/send#create" }
  end

  teardown do
    Rails.application.routes.disable_clear_and_finalize = false
    Rails.application.reload_routes!
  end

  test "unconfirmed users can't send to clients" do
    user = users(:unconfirmed)
    Business.create!(name: "Unconfirmed Co", owner: user)
    sign_in user
    post "/test_send"
    assert_redirected_to admin_root_path
    assert_match "Confirm your email", flash[:alert]
  end

  test "confirmed users can" do
    sign_in users(:one)
    post "/test_send"
    assert_response :ok
  end
end
