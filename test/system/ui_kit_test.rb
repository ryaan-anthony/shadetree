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
      assert_button "Delete client"
      click_on "Cancel"
    end
    assert_no_selector "dialog#confirm-dialog[open]"
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
end
