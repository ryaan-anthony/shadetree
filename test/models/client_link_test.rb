require "test_helper"

class ClientLinkTest < ActiveSupport::TestCase
  include ClientLinkDocumentHelpers

  setup do
    create_test_document_table
    @business = businesses(:one)
    @document = create_test_document(@business)
    @link = as_business(@business) { ClientLink.issue!(@document, actions: %w[approve]) }
  end

  test "tokens are long, random, base58 and not stored" do
    assert_equal ClientLink::TOKEN_LENGTH, @link.token.length
    assert_match(/\A[1-9A-HJ-NP-Za-km-z]+\z/, @link.token)
    assert_not_includes @link.attributes.values.map(&:to_s), @link.token
    other = as_business(@business) { ClientLink.issue!(@document) }
    assert_not_equal @link.token, other.token
    assert_equal @link.token, ClientLink.find_by_token(@link.token).token, "the token is stable"
  end

  test "lookup finds the link across businesses and rejects malformed tokens" do
    assert_equal @link, ClientLink.find_by_token(@link.token)
    assert_nil ClientLink.find_by_token(@link.token.succ)
    assert_nil ClientLink.find_by_token(@link.id.to_s)
    assert_nil ClientLink.find_by_token(nil)
    assert_nil ClientLink.find_by_token("0" * ClientLink::TOKEN_LENGTH) # not base58
  end

  test "expiry follows the document's policy (nil: no expiry), or 90 days without one" do
    assert_in_delta 30.days.from_now, @link.expires_at, 5.seconds
    never = Class.new(ClientLinkDocumentHelpers::TestDocument) { def client_link_expires_at = nil }
    doc = as_business(@business) { never.create!(title: "x") }
    assert_nil as_business(@business) { ClientLink.issue!(doc) }.expires_at
    plain = Class.new(ClientLinkDocumentHelpers::TestDocument) { undef_method :client_link_expires_at if method_defined?(:client_link_expires_at) }
    doc = as_business(@business) { plain.create!(title: "y") }
    assert_in_delta 90.days.from_now, as_business(@business) { ClientLink.issue!(doc) }.expires_at, 5.seconds
  end

  test "status covers active, expired, revoked and suspended businesses" do
    assert_equal :active, @link.status
    travel 31.days do
      assert_equal :expired, @link.status
      assert_not @link.allows?(:approve)
    end
    @link.revoke!
    assert_equal :revoked, @link.status
    @link.update_columns(revoked_at: nil)
    @business.update!(active: false)
    assert_equal :unavailable, @link.reload.status
  end

  test "reissue revokes the old link and keeps document and actions" do
    fresh = as_business(@business) { @link.reissue! }
    assert @link.reload.revoked_at
    assert_equal [ @document, %w[approve] ], [ fresh.linkable, fresh.actions ]
    assert_not_equal @link.token, fresh.token
  end

  test "one-time actions happen once and only when allowed" do
    ran = 0
    assert @link.perform_once!(:approve) { ran += 1 }
    assert_not @link.perform_once!(:approve) { ran += 1 }
    assert_equal 1, ran
    assert @link.performed?(:approve)
    assert_not @link.perform_once!(:pay), "pay isn't on this link"
  end

  test "a failed action block leaves no record, so the client can retry" do
    assert_raises(RuntimeError) { @link.perform_once!(:approve) { raise "payment failed" } }
    assert_not @link.performed?(:approve)
  end

  test "views are counted" do
    @link.record_view!(device: "Phone · Safari")
    @link.record_view!
    assert_equal 2, @link.views_count
    assert @link.first_viewed_at <= @link.last_viewed_at
  end

  test "links must point at a document in their own business" do
    other_doc = create_test_document(businesses(:two))
    link = as_business(@business) { ClientLink.new(linkable: other_doc, business: @business) }
    assert_not link.valid?
    assert_includes link.errors[:linkable], "belongs to another business"
  end

  test "unknown actions are rejected" do
    assert_raises(ActiveRecord::RecordInvalid) { as_business(@business) { ClientLink.issue!(@document, actions: %w[delete]) } }
  end

  test "device descriptions are coarse" do
    assert_equal "Phone · Safari", ClientDevice.describe("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
    assert_equal "Computer · Chrome", ClientDevice.describe("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36")
    assert_equal "Unknown", ClientDevice.describe(nil)
  end

  test "rotating secret_key_base invalidates old links" do
    token = @link.token
    Rails.application.singleton_class.define_method(:secret_key_base) { "rotated" * 10 }
    assert_nil ClientLink.find_by_token(token)
  ensure
    Rails.application.singleton_class.remove_method(:secret_key_base)
  end

  test "a revoke that lands after the link was loaded still blocks the action" do
    stale = ClientLink.find_by_token(@link.token)
    ClientLink.find_by_token(@link.token).revoke!
    ran = false
    assert_not stale.perform_once!(:approve) { ran = true }
    assert_not ran
  end

  test "uniqueness errors from the action itself are raised, not mistaken for a repeat" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      @link.perform_once!(:approve) { raise ActiveRecord::RecordNotUnique, "from the action" }
    end
    assert_not @link.performed?(:approve)
  end

  test "deleting a user keeps the links they created or revoked" do
    user = User.create!(email: "leaver@example.com", password: "password123", confirmed_at: Time.current)
    link = as_business(@business) { ClientLink.issue!(@document, by: user) }
    link.revoke!(by: user)
    user.destroy!
    assert_nil link.reload.created_by_id
    assert_nil link.revoked_by_id
  end

  test "path redaction" do
    assert_equal 'Started GET "/c/[FILTERED]" for x', SecretPathLogger.redact('Started GET "/c/abc123" for x')
    assert_equal "/invitations/[FILTERED]/accept", SecretPathLogger.redact("/invitations/abc/accept")
  end
end
