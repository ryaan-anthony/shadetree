require "application_system_test_case"

# Behavior of the UI kit's interactive pieces (PLT-05), exercised through the style guide.
class UiKitTest < ApplicationSystemTestCase
  test "modal opens, traps focus and closes on Escape" do
    visit styleguide_path
    click_on "Open modal"
    assert_selector "dialog#sample-modal[open]"
    assert_text "Reschedule visit"

    find("dialog#sample-modal").send_keys(:escape)
    assert_no_selector "dialog#sample-modal[open]"
  end

  test "data-turbo-confirm uses the kit's confirm dialog" do
    visit styleguide_path
    click_link "Delete client"
    within "dialog#confirm-dialog[open]" do
      assert_text "Delete Maria Lopez?"
      assert_selector "button.btn-destructive-solid", text: "Delete client" # data-turbo-confirm-variant="destructive" (PLT-14)
      assert_selector "button.btn-tertiary", text: "Cancel"
      click_on "Cancel"
    end
    assert_no_selector "dialog#confirm-dialog[open]"
    assert_equal "confirm-dialog-message", find("dialog#confirm-dialog", visible: :all)["aria-describedby"] # the message is read out
  end

  # PLT-14 (owner, 2026-11-22): a safe action confirms with the Primary.
  test "a confirm that isn't destructive uses the Primary" do
    visit styleguide_path
    click_link "Complete job"
    within "dialog#confirm-dialog[open]" do
      assert_selector "button.btn-primary", text: "Complete job"
      click_on "Cancel"
    end
  end

  test "menu opens with the keyboard and closes on Escape" do
    visit styleguide_path
    button = find_button("Actions")
    button.click
    assert_selector "[data-menu-target='menu']:not([hidden])"
    find(".menu-item", text: "Edit").send_keys(:escape)
    assert_selector "[data-menu-target='menu'][hidden]", visible: :all
    assert_equal "false", button["aria-expanded"]
  end

  test "toasts can be dismissed" do
    visit styleguide_path(toast: 1)
    within("#flash") { click_on "Dismiss" }
    assert_no_selector ".toast"
  end
end

class StaffShellTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  teardown do
    Warden.test_reset!
    page.current_window.resize_to(1400, 1400) # windows are reused across tests
  end

  test "phone-sized screens get a navigation drawer" do
    page.current_window.resize_to(390, 844)
    visit admin_root_path
    assert_no_selector "#app-sidebar[data-open='true']"

    click_on "Open navigation"
    assert_selector "#app-sidebar[data-open='true']"
    assert_link "Settings"

    page.send_keys(:escape)
    assert_no_selector "#app-sidebar[data-open='true']"
  end

  test "desktop shows the sidebar with the business switcher" do
    page.current_window.resize_to(1400, 1400)
    visit admin_root_path
    assert_selector "#app-sidebar .biz-switch"
    find(".biz-switch").click
    assert_text "Switch business"
  end

  # PLT-22: two drop areas on one page; a drop on either is that one's, and each one's
  # page-level guard (against a near miss opening the file) leaves the other alone.
  test "with two drop areas, each takes the files dropped on it" do
    visit styleguide_path(anchor: "forms")
    dropped = evaluate_script(<<~JS)
      (() => {
        const transfer = new DataTransfer()
        transfer.items.add(new File([new Uint8Array(10)], "site.png", { type: "image/png" }))
        let effect = "none" // a script's DataTransfer ignores dropEffect, so record what's set
        Object.defineProperty(transfer, "dropEffect", { get: () => effect, set: (value) => { effect = value } })
        const zone = document.querySelectorAll(".file-drop-zone")[1]
        const events = ["dragenter", "dragover", "drop"].map((kind) => new DragEvent(kind, { bubbles: true, cancelable: true, dataTransfer: transfer }))
        events.forEach((event) => zone.dispatchEvent(event))
        return events[1].dataTransfer.dropEffect
      })()
    JS
    assert_equal "copy", dropped
    drop_areas = all(".file-drop", count: 2)
    within(drop_areas[1]) { assert_selector ".file-drop-chosen", text: "site.png" }
    within(drop_areas[0]) { assert_no_selector ".file-drop-chosen" }
  end
end
