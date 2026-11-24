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

  # PLT-19: the kit menu, by keyboard alone; it's as wide as its longest item.
  test "menu keys: arrow down opens, Home and End, Tab moves on and closes" do
    visit styleguide_path
    button = find_button("Actions")
    button.send_keys(:down)
    assert_equal "true", button["aria-expanded"]
    assert_equal "Edit", evaluate_script("document.activeElement.textContent").strip
    page.send_keys(:end)
    assert_equal "Delete", evaluate_script("document.activeElement.textContent").strip
    page.send_keys(:home)
    assert_equal "Edit", evaluate_script("document.activeElement.textContent").strip
    page.send_keys(:up)
    assert_equal "Delete", evaluate_script("document.activeElement.textContent").strip, "wraps round"
    heights = [ "Edit", "Duplicate for another client" ].map { evaluate_script("arguments[0].getBoundingClientRect().height", find(".menu-item", text: _1)) }
    assert_equal heights.first, heights.last, "the long item doesn't wrap"
    page.send_keys(:tab)
    assert_equal "false", button["aria-expanded"]
    assert_selector "##{button["aria-controls"]}[hidden]", visible: :all
  end

  test "segmented radios move with the arrow keys" do
    visit styleguide_path
    find("#sg-segmented-radios input[value=monthly]", visible: :all).send_keys(:right)
    assert find("#sg-segmented-radios input[value=yearly]", visible: :all).checked?
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

  # #456: closed, the phone drawer is inert, so Tab can't reach its links; open, it can.
  test "the closed phone drawer is skipped by Tab, the open one and the desktop sidebar aren't" do
    page.current_window.resize_to(390, 844)
    visit admin_root_path
    assert_selector "#app-sidebar[inert]", visible: :all
    find("button[aria-label='Open navigation']").send_keys(:tab) # Tab from the top bar on
    assert_not tabs_reach_sidebar?, "Tab reached a link in the closed drawer"

    find("button[aria-label='Open navigation']").send_keys(:enter) # the skip link, focused, covers it
    assert_no_selector "#app-sidebar[inert]"
    assert tabs_reach_sidebar?, "the open drawer's links can't be reached"
    page.send_keys(:escape)
    assert_equal "Open navigation", evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_selector "#app-sidebar[inert]", visible: :all

    page.current_window.resize_to(1280, 900)
    assert_no_selector "#app-sidebar[inert]"
    visit admin_root_path
    assert_no_selector "#app-sidebar[inert]"
    assert tabs_reach_sidebar?, "the desktop sidebar's links can't be reached"
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

  private

  # Presses Tab up to `presses` times; true once focus lands on a link or button in the sidebar.
  def tabs_reach_sidebar?(presses: 40)
    presses.times.any? do
      page.driver.browser.action.send_keys(:tab).perform
      evaluate_script("!!document.activeElement?.closest('#app-sidebar') && document.activeElement.matches('a, button')")
    end
  end
end
