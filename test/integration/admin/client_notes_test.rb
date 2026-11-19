require "test_helper"

# CLI-05 part 2: notes on the timeline (edited only by their author), each job's next visit
# and what the client has paid in all.
class Admin::ClientNotesTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @maria = as_business(@business) do
      Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ])
    end
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "a note goes on the timeline; its author can edit it, others can't" do
    get admin_client_path(@maria)
    assert_select "form[action=?] textarea[name='client_note[body]']", admin_client_notes_path(@maria)
    post admin_client_notes_path(@maria), params: { client_note: { body: "  Called about the side gate <b>code</b>  " } }
    assert_redirected_to admin_client_path(@maria, anchor: "client-timeline")
    note = as_business(@business) { @maria.timeline_notes.sole }
    assert_equal [ "Called about the side gate <b>code</b>", @owner ], [ note.body, note.user ]
    follow_redirect!
    assert_select "#client-timeline li", /Called about the side gate <b>code<\/b>/
    assert_select "#client-timeline a[href=?]", edit_admin_client_note_path(@maria, note), "Edit"

    patch admin_client_note_path(@maria, note), params: { client_note: { body: "" } }
    assert_response :unprocessable_content
    patch admin_client_note_path(@maria, note), params: { client_note: { body: "Gate code is on file" } }
    follow_redirect!
    assert_select "#client-timeline li", /Gate code is on file.*edited/m

    post admin_client_notes_path(@maria), params: { client_note: { body: " " } }
    assert_response :unprocessable_content
    assert_select ".field", /can't be empty/
    long = Array.new(50) { "x" * 99 }.join("\r\n") # 4,999 characters as the browser counts them
    post admin_client_notes_path(@maria), params: { client_note: { body: long } }
    assert_response :redirect
    patch admin_client_note_path(@maria, note), params: { client_note: { body: "Gate code is on file" } }
    assert_equal 1, as_business(@business) { note.reload.edited_at ? 1 : 0 }
    edited = as_business(@business) { note.reload.edited_at }
    travel 1.minute do
      patch admin_client_note_path(@maria, note), params: { client_note: { body: "Gate code is on file" } }
    end
    assert_equal edited, as_business(@business) { note.reload.edited_at }, "unchanged isn't an edit"

    admin = member_with_role("admin", business: @business)
    sign_in admin
    post switch_admin_business_path, params: { business: @business.uid }
    get admin_client_path(@maria)
    assert_select "#client-timeline a[href=?]", edit_admin_client_note_path(@maria, note), 0
    patch admin_client_note_path(@maria, note), params: { client_note: { body: "Mine now" } }
    assert_match "Only the person who wrote", flash[:alert]
    assert_equal "Gate code is on file", as_business(@business) { note.reload.body }
  end

  test "technicians can't add notes; another business's client or note isn't found" do
    note = as_business(@business) { @maria.timeline_notes.create!(business: @business, user: @owner, body: "Mine") }
    sign_out :user
    assert_permission_matrix(technician: false) { post admin_client_notes_path(@maria), params: { client_note: { body: "x" } } }
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    theirs, their_note = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      [ client, client.timeline_notes.create!(business: client.business, body: "Theirs") ]
    end
    assert_not_found_across_businesses { post admin_client_notes_path(theirs), params: { client_note: { body: "x" } } }
    assert_not_found_across_businesses { get edit_admin_client_note_path(@maria, their_note) }
    assert_not_found_across_businesses { patch admin_client_note_path(theirs, note), params: { client_note: { body: "x" } } }
  end

  test "jobs show their next visit; the balance card shows what's been paid in all" do
    as_business(@business) do
      job = Job.create!(client: @maria, title: "Spring cleanup", line_items_attributes: [ { name: "Mowing", quantity: 1, unit_price: "200" } ])
      job.visits.new(scheduled_on: @business.today + 3, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
      invoice = Invoice.from_job!(job)
      invoice.update!(tax_rates: [])
      invoice.mark_sent!(by: @owner, channel: "link")
      invoice.record_payment!(by: @owner, amount: "75", received_on: @business.today, payment_method: "cash")
    end
    get admin_client_path(@maria)
    assert_select "li", /Spring cleanup.*Next visit/m
    assert_select "#client-lifetime-paid", /Paid in all: \$75\.00/

    as_business(@business) do
      job = Job.create!(client: @maria, title: "Gutters", line_items_attributes: [ { name: "Gutters", quantity: 1, unit_price: "50" } ])
      job.visits.new(scheduled_on: @business.today + 2, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
      job.visits.new(scheduled_on: @business.today + 9, timing: "anytime").tap { _1.schedule!(by: @owner, notify_client: false) }
      job.visits.first.update_columns(scheduled_on: @business.today - 2)
    end
    get admin_client_path(@maria)
    assert_select "li .text-danger", /Overdue visit/
  end

  test "a note by someone who left still shows, and nobody can edit it; notes are escaped on the next page too" do
    leaver = member_with_role("admin", business: @business)
    note = as_business(@business) { @maria.timeline_notes.create!(business: @business, user: leaver, body: "<script>x</script>") }
    BusinessUser.where(user: leaver).update_all(active: false)
    as_business(@business) { 30.times { |i| ClientEvent.record!(@maria, :visit_cancelled, when: "d#{i}", at: (i + 1).days.from_now) } }
    get admin_client_path(@maria)
    last = as_business(@business) { @maria.events.timeline.offset(ClientEvent::PAGE_SIZE - 1).first }
    get timeline_admin_client_path(@maria, before: last.uid), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_match "&lt;script&gt;x&lt;/script&gt;", response.body
    assert_match leaver.full_name, response.body
    assert_no_match edit_admin_client_note_path(@maria, note), response.body
  end
end
