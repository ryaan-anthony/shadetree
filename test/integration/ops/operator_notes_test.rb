require "test_helper"

# OPS-02: internal notes on a business (only their author edits or deletes them, never shown to
# the business) and finding a person by email.
class Ops::OperatorNotesTest < ActionDispatch::IntegrationTest
  setup { @business = businesses(:one) }

  test "operators add notes; only the author edits or deletes them; each change is audited" do
    sign_in_operator
    post ops_business_notes_path(@business), params: { operator_note: { body: "  Beta customer, comp until spring.  " } }
    assert_redirected_to ops_business_path(@business, anchor: "notes")
    note = @business.operator_notes.last
    assert_equal "Beta customer, comp until spring.", note.body
    assert_equal users(:one), note.author
    entry = AuditEntry.find_by!(action: "business.note_added")
    assert_equal [ @business, note.id ], [ entry.business, entry.data["note"] ]
    assert_no_match "comp until spring", entry.to_json, "the note's text stays out of the log"

    post ops_business_notes_path(@business), params: { operator_note: { body: " " } }
    assert_match "can't be blank", flash[:alert]

    get ops_business_path(@business)
    assert_select "#note-#{note.id}", /Beta customer/
    assert_select "#note-#{note.id}", /user1@example.com/
    get edit_ops_business_note_path(@business, note)
    assert_response :success
    patch ops_business_note_path(@business, note), params: { operator_note: { body: "Comp until June." } }
    assert_equal "Comp until June.", note.reload.body
    patch ops_business_note_path(@business, note), params: { operator_note: { body: "" } }
    assert_response :unprocessable_content
    assert AuditEntry.exists?(action: "business.note_edited", business: @business)
    assert_no_difference(-> { AuditEntry.where(action: "business.note_edited").count }, "saving without a change records nothing") do
      patch ops_business_note_path(@business, note), params: { operator_note: { body: "Comp until June." } }
    end

    other = @business.operator_notes.create!(body: "Someone else's", author: users(:two))
    get ops_business_path(@business)
    assert_select "#note-#{other.id} form", 0
    users(:two).update_columns(deleted_at: Time.current, email: "deleted-user-#{users(:two).id}@deleted.invalid")
    get ops_business_path(@business)
    assert_select "#note-#{other.id}", /A former operator/
    assert_no_match "deleted-user-", css_select("#notes").text
    get edit_ops_business_note_path(@business, other)
    assert_response :not_found
    delete ops_business_note_path(@business, other)
    assert_response :not_found
    delete ops_business_note_path(businesses(:two), note)
    assert_response :not_found, "a note is found only under its own business"

    delete ops_business_note_path(@business, note)
    assert_not OperatorNote.exists?(note.id)
    assert AuditEntry.exists?(action: "business.note_deleted", business: @business)
  end

  test "signed out, or before entering a code, notes and the people lookup aren't reachable" do
    note = @business.operator_notes.create!(body: "x", author: users(:one))
    get ops_users_path(email: "user")
    assert_response :not_found
    post ops_business_notes_path(@business), params: { operator_note: { body: "x" } }
    assert_response :not_found
    Operator.grant!(users(:one))
    sign_in users(:one)
    get ops_users_path(email: "user")
    assert_redirected_to ops_two_factor_setup_path
    get edit_ops_business_note_path(@business, note)
    assert_redirected_to ops_two_factor_setup_path
  end

  test "notes are never shown to the business, and non-operators can't reach them" do
    note = @business.operator_notes.create!(body: "Internal: slow payer", author: users(:two))
    sign_in users(:one)
    get admin_root_path
    assert_no_match "slow payer", response.body
    post ops_business_notes_path(@business), params: { operator_note: { body: "x" } }
    assert_response :not_found
    delete ops_business_note_path(@business, note)
    assert_response :not_found
    get ops_users_path(email: "user")
    assert_response :not_found
  end

  test "a person is found by email with their memberships" do
    sign_in_operator
    get ops_users_path
    assert_select "#users", 0
    get ops_users_path(email: "USER1@")
    assert_select "#user-#{users(:one).id}" do
      assert_select "li", 2
      assert_select "li", /Test Business Two.*Technician/m
    end
    get ops_users_path(email: "nobody-here")
    assert_select "#no-users"
  end
end
