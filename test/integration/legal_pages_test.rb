require "test_helper"

# MKT-03: the legal and trust pages, their versions, acceptance at sign-up and re-acceptance.
class LegalPagesTest < ActionDispatch::IntegrationTest
  include ClientLinkDocumentHelpers

  # A material update to the Terms, in force from 2027-01-01.
  def with_material_terms_update
    original = LegalDocument::ALL
    updated = original.merge("terms" => LegalDocument.new("terms", "Terms of Service", "x", [
      LegalDocument::FIRST, { version: "2027-01-01", effective_on: Date.new(2027, 1, 1), summary: "New billing terms.", material: true }
    ])).freeze
    LegalDocument.send(:remove_const, :ALL)
    LegalDocument.const_set(:ALL, updated)
    travel_to(Date.new(2027, 1, 10)) { yield }
  ensure
    LegalDocument.send(:remove_const, :ALL)
    LegalDocument.const_set(:ALL, original)
  end

  test "every page shows its effective date, a draft notice and its history; earlier versions stay readable" do
    get legal_path
    assert_select "#legal-documents li", LegalDocument::ALL.size
    LegalDocument::ALL.each_value do |document|
      get legal_document_path(document.slug)
      assert_response :success, document.slug
      assert_select "h1", document.title
      assert_select "#effective-date", /Effective November 18, 2026/
      assert_select "#draft-notice"
      assert_select "#change-history li a[href=?]", legal_document_path(document.slug, "2026-11-18")
      get legal_document_path(document.slug, "2026-11-18")
      assert_response :success
    end
    get terms_path
    assert_select "h1", "Terms of Service"
    get privacy_path
    assert_select "h1", "Privacy Policy"
    get legal_document_path("terms", "2001-01-01")
    assert_response :not_found
    get "/legal/nope"
    assert_response :not_found
  end

  test "signing up records the versions accepted, and when" do
    post user_registration_path, params: { user: { first_name: "Ana", last_name: "Silva", email: "ana@example.com", password: "long enough phrase", terms_of_service: "1" } }
    user = User.find_by!(email: "ana@example.com")
    assert_equal [ "2026-11-18", "2026-11-18" ], [ user.terms_version, user.privacy_version ]
    assert user.terms_accepted_at
  end

  test "a material update is accepted on the next visit to the app, then you carry on where you were going" do
    sign_in users(:one)
    with_material_terms_update do
      get admin_clients_path
      assert_redirected_to legal_acceptance_path
      follow_redirect!
      assert_select "li", /Terms of Service.*New billing terms/m
      post legal_acceptance_path
      assert_response :unprocessable_content
      post legal_acceptance_path, params: { accept: "1" }
      assert_redirected_to admin_clients_path
      assert_equal "2027-01-01", users(:one).reload.terms_version
      get admin_clients_path
      assert_response :success
    end
  end

  test "while a material update waits, lookups and frames are refused without saving where to return" do
    sign_in users(:one)
    with_material_terms_update do
      post search_admin_clients_path(format: :json), params: { q: "a" }
      assert_response :forbidden
      get new_admin_client_path(inline: 1), headers: { "Turbo-Frame" => "new_client" }
      assert_response :forbidden
      post admin_clients_path, params: { client: { display_name: "X" } }
      assert_redirected_to legal_acceptance_path
      assert_nil session[:after_legal_acceptance]
      post legal_acceptance_path, params: { accept: "1" }
      assert_redirected_to admin_root_path
    end
  end

  test "nothing to accept today: no prompt" do
    sign_in users(:one)
    get admin_root_path
    assert_response :success
    get legal_acceptance_path
    assert_redirected_to admin_root_path
  end

  test "legal links in the marketing footer, the app, client pages and client emails" do
    get root_path
    assert_select "#legal-links a", LegalDocument::ALL.size
    sign_in users(:one)
    get admin_root_path
    assert_select ".side-foot a[href=?]", privacy_path

    create_test_document_table
    business = businesses(:one)
    link = as_business(business) { ClientLink.issue!(create_test_document(business), actions: %w[approve]) }
    get client_link_path(link.token)
    get privacy_path
    assert_select "h2#clients"
    get client_link_path(link.token)
    assert_select "footer a[href=?]", privacy_url(anchor: "clients"), "Privacy (Shadetree)"

    mail = ClientMailer.with(business_id: business.id, to: "maria@example.com", recipient_name: "Maria").test_message
    assert_match %r{href="http://[^"]+/privacy#clients"}, mail.html_part.body.to_s
    assert_match %r{How your details are handled: http://\S+/privacy#clients}, mail.text_part.body.to_s
  end
end
