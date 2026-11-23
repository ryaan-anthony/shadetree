require "application_system_test_case"

# PLT-22: Branding's logo drop area (the kit's file upload), in a browser and without JavaScript.
class LogoUploadTest < ApplicationSystemTestCase
  include AxeHelpers

  setup do
    @business = businesses(:one)
    visit new_user_session_path
    sign_in_with_form(users(:one).email, "password123")
    assert_text "Home"
    visit edit_admin_business_path(tab: "branding")
  end

  test "a logo dropped on the drop area is previewed, then saved" do
    within(".file-drop") do
      assert_text "Drop your logo here, or browse"
      assert_text "PNG, JPEG or WebP, up to 5 MB."
      assert_selector "input#business_logo[type=file]", visible: :all # the real input, kept for keyboard and screen readers
    end
    assert evaluate_script("(() => { const input = document.getElementById('business_logo'); input.focus(); return document.activeElement === input })()"),
           "the hidden file input can still take focus"

    drop_file "logo.png", "image/png", file_fixture("logo.png").binread
    within(".file-drop-chosen") do
      assert_text "logo.png"
      assert_selector "img.file-drop-thumb[src^='blob:']"
    end
    assert_selector "aside[aria-label=Preview] img[src^='blob:']"
    assert_empty axe_problems("Branding with a chosen logo")

    click_on "Save branding"
    assert_text "Settings saved."
    assert_selector "img[alt='Your current logo']"
    assert @business.reload.logo.attached?
  end

  test "a wrong type or a file over 5 MB is refused before saving" do
    drop_file "logo.gif", "image/gif", file_fixture("logo.gif").binread
    assert_selector "#business_logo_check", text: "Logo must be a PNG, JPEG or WebP image"
    assert_selector "[data-file-drop-target=announce]", text: "logo.gif: Logo must be a PNG, JPEG or WebP image", visible: :all
    assert_selector "input#business_logo[aria-invalid=true]", visible: :all
    assert_no_selector "img.file-drop-thumb"
    assert_no_selector "aside[aria-label=Preview] img[src^='blob:']"

    drop_file "huge.png", "image/png", nil, LogoUpload::MAX_BYTES + 1
    assert_selector "#business_logo_check", text: "Logo must be smaller than 5 MB"

    click_on "Clear huge.png"
    assert_no_selector ".file-drop-chosen"
    assert_no_selector "#business_logo_check" # hidden again
    assert_selector "input#business_logo[aria-invalid=false]", visible: :all
  end

  test "a file dropped beside the drop area doesn't leave the page" do
    fill_in "Hex", with: "#9a3412" # unsaved
    prevented = evaluate_script(<<~JS)
      (() => {
        const transfer = new DataTransfer()
        transfer.items.add(new File([new Uint8Array(10)], "logo.png", { type: "image/png" }))
        const drop = new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer })
        document.querySelector("h1").dispatchEvent(drop)
        return drop.defaultPrevented
      })()
    JS
    assert prevented
    assert_field "Hex", with: "#9a3412"
    assert_no_selector ".file-drop-chosen"
  end

  test "the server's refusal is set aside once a new file passes" do
    drop_file "logo.gif", "image/gif", file_fixture("logo.gif").binread
    click_on "Save branding"
    assert_selector "#business_logo_error", text: "Logo must be a PNG, JPEG or WebP image"
    assert_selector "input#business_logo[aria-describedby~=business_logo_error]", visible: :all

    drop_file "logo.png", "image/png", file_fixture("logo.png").binread
    assert_no_selector "#business_logo_error"
    assert_no_selector "input#business_logo[aria-describedby~=business_logo_error]", visible: :all
    assert_selector "input#business_logo[aria-invalid=false]", visible: :all
  end

  test "without JavaScript the plain file field still uploads" do
    Capybara.using_driver(:rack_test) do # page.visit: there are no controllers to wait for
      page.visit new_user_session_path
      fill_in "Email", with: users(:one).email
      fill_in "Password", with: "password123"
      click_button "Sign in"
      page.visit edit_admin_business_path(tab: "branding")
      assert_no_selector ".file-drop[data-enhanced]"
      attach_file "Upload a logo", file_fixture("logo.png").to_s
      click_on "Save branding"
      assert_text "Settings saved."
      assert_selector "img[alt='Your current logo']"
    end
    assert @business.reload.logo.attached?
  end

  private

  # Drops a file built in the page (from `data`, or `size` zero bytes) on the drop area, as a
  # drag from the desktop would.
  def drop_file(name, type, data, size = nil)
    execute_script(<<~JS, name, type, data && Base64.strict_encode64(data), size)
      const [name, type, base64, size] = arguments
      const bytes = base64 ? Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)) : new Uint8Array(size)
      const transfer = new DataTransfer()
      transfer.items.add(new File([bytes], name, { type }))
      const zone = document.querySelector(".file-drop-zone")
      for (const kind of ["dragenter", "dragover", "drop"]) zone.dispatchEvent(new DragEvent(kind, { bubbles: true, cancelable: true, dataTransfer: transfer }))
    JS
  end
end
