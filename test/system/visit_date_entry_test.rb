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
    # The crew of one this business has: its owner works visits, so they're ticked.
    assert_equal [ users(:one).id ], as_business(@business) { @business.business_users.active.select { _1.can?(:field_work) }.map(&:user_id) }
    visit new_admin_job_visit_path(@job)
    field = find_field("Date (or first day)")
    # Blur, then focus by script, so the cursor starts in the first part. Which part that is
    # depends on the browser's locale (month first in the US, day first in the UK), so the
    # keystrokes follow its order.
    keys = evaluate_script(<<~JS)
      new Intl.DateTimeFormat(undefined, { year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(new Date(2026, 11, 23))
        .filter((p) => ["year", "month", "day"].includes(p.type)).map((p) => p.value).join("")
    JS
    execute_script("arguments[0].blur(); arguments[0].focus()", field)
    field.send_keys(keys)
    assert_field "Date (or first day)", with: "2026-12-23"

    covered = evaluate_script(<<~JS)
      (() => { const r = document.getElementById("visit_scheduled_on").getBoundingClientRect()
               return document.elementFromPoint(r.right - 12, r.top + r.height / 2)?.id })()
    JS
    assert_equal "visit_scheduled_on", covered
    assert_selector "input[name='visit[assignee_ids][]'][type=checkbox]:checked", count: 1
    assert_selector "#sole-crew-hint", text: "You're the only one on the team who works visits."
  end
end
