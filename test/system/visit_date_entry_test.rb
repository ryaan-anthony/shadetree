require "application_system_test_case"

# #289: a visit's date can be typed (the review couldn't, with its tool), and the browser's own
# picker stays reachable: nothing covers the field's calendar button.
class VisitDateEntryTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @job = as_business(@business) do
      client = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Job.create!(client:, title: "Ants")
    end
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
  end

  test "typing a date fills it in, and the picker button is the field's own" do
    visit new_admin_job_visit_path(@job)
    field = find_field("Date (or first day)")
    field.click
    execute_script("arguments[0].focus()", field) # the month part first
    field.send_keys("12232026")
    assert_equal "2026-12-23", field.value

    covered = evaluate_script(<<~JS)
      (() => { const r = document.getElementById("visit_scheduled_on").getBoundingClientRect()
               return document.elementFromPoint(r.right - 12, r.top + r.height / 2)?.id })()
    JS
    assert_equal "visit_scheduled_on", covered
    assert_selector "input[name='visit[assignee_ids][]'][type=checkbox]:checked", count: 1 # the one-person crew is going
  end
end
