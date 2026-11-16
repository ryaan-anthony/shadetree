require "test_helper"

# QTE-05: Owners and Admins record an approval the client gave another way.
class Admin::QuoteApprovalsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
      Quote.start(client: maria).tap do
        _1.sync_line_items([ { "key" => "a", "name" => "Leaf cleanup", "quantity" => "1", "unit_price" => "180" } ])
        _1.save!
        _1.mark_sent!(by: users(:one), channel: "link")
      end
    end
  end

  def mark_approved(note: "Approved on the phone")
    post admin_quote_approval_path(@quote), params: { quote_response: { signer_name: "Maria Lopez", message: note } }
  end

  def sign_in_owner
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "only Owners and Admins can mark a quote approved" do
    assert_permission_matrix(owner: true, admin: true, technician: false) { mark_approved }
  end

  test "records who did it and the note, tells the rest of the team, and doesn't email the client" do
    admin = member_with_role(:admin)
    sign_in_owner
    get preview_admin_quote_path(@quote)
    assert_select "form[action=?] input[name='quote_response[signer_name]'][value='Maria Lopez']", admin_quote_approval_path(@quote)

    mark_approved
    assert_redirected_to preview_admin_quote_path(@quote)
    approval = as_business(@business) { @quote.reload.approval }
    assert_equal [ "approved", users(:one).id, "Approved on the phone" ], [ @quote.status, approval.recorded_by_id, approval.message ]
    assert_nil approval.client_link_id

    perform_enqueued_jobs
    assert_equal [ [ admin.email ] ], ActionMailer::Base.deliveries.map(&:to)
    assert_equal "Quote #{@quote.number} marked approved by #{users(:one).full_name}", ActionMailer::Base.deliveries.sole.subject

    follow_redirect!
    assert_select "#responses-h", "Client response"
    assert_select "li[id^=response-]", /Approved.*recorded by #{users(:one).full_name} for Maria Lopez.*Approved on the phone/m
    assert_select "button", { text: /Mark approved/, count: 0 }
  end

  test "a note is required, and an answered quote can't be marked approved" do
    sign_in_owner
    mark_approved(note: "")
    assert_equal "Add a note about how the client approved.", flash[:alert]
    assert_equal "sent", as_business(@business) { @quote.reload.status }

    as_business(@business) { @quote.record_response!(:decline) }
    mark_approved
    assert_equal "Quote #{@quote.number} can't be marked approved: it's declined.", flash[:alert]
  end

  test "an approved quote is locked from editing" do
    sign_in_owner
    mark_approved
    get edit_admin_quote_path(@quote)
    assert_redirected_to admin_quotes_path
    patch admin_quote_path(@quote), params: { quote: { title: "Changed" } }
    assert_redirected_to admin_quotes_path
    assert_nil as_business(@business) { @quote.reload.title }
  end

  test "another business's quote isn't found" do
    sign_in users(:two)
    assert_not_found_across_businesses { mark_approved }
  end
end
