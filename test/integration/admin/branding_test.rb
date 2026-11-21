require "test_helper"

# CAT-02: the Branding settings tab and where branding shows.
class Admin::BrandingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "only owners and admins change branding" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get edit_admin_business_path(tab: "branding") }
    assert_permission_matrix(owner: true, admin: true, technician: false) do
      patch admin_business_path(tab: "branding"), params: { business: { brand_color: "#9a3412" } }
    end
  end

  test "the tab offers an upload, presets, a custom color and a live preview" do
    get edit_admin_business_path(tab: "branding")
    assert_select "form[enctype='multipart/form-data'] input[type=file][name='business[logo]']"
    assert_select "input[name='business[logo_url]']", false
    assert_select "button[data-brand-preview-target=swatch]", Branding::PRESETS.size
    assert_select "input#business_brand_color"
    assert_select "aside[aria-label=Preview] [data-brand-preview-target=preview]", /Approve quote/
    # QA #274: the same sample quote as the Features page, and labelled a sample.
    assert_select "aside[aria-label=Preview]", /Quote Q-0001\s*Sample.*Spring cleanup.*\$622\.05/m
    assert_select "aside[aria-label=Preview] .wordmark.wordmark-small", "Shadetree" # 11px: one colour (owner, 2026-11-21)
  end

  test "uploading a logo and picking a color" do
    patch admin_business_path(tab: "branding"), params: { business: { brand_color: "#9a3412", logo: fixture_file_upload("logo.png", "image/png") } }
    assert_redirected_to edit_admin_business_path(tab: "branding")
    assert_equal "#9a3412", @business.reload.brand_color
    assert @business.logo.attached?
    follow_redirect!
    assert_select "img[alt='Your current logo']"
    assert_select "input[type=checkbox][name='business[remove_logo]']"
  end

  test "a bad upload is explained beside the field" do
    patch admin_business_path(tab: "branding"), params: { business: { logo: fixture_file_upload("logo.gif", "image/gif") } }
    assert_response :unprocessable_content
    assert_select ".error-text", /Logo must be a PNG, JPEG or WebP image/
    assert_not @business.reload.logo.attached?
  end

  test "a failed save keeps showing the saved logo" do
    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    patch admin_business_path(tab: "branding"), params: { business: { brand_color: "orange", logo: fixture_file_upload("logo.png", "image/png") } }
    assert_response :unprocessable_content
    assert_select "img[alt='Your current logo']"
    assert_select "input[name='business[remove_logo]']"
    assert_select ".biz-switch .biz-logo img"
    assert_select "input#business_logo[aria-describedby~=logo-check]"
  end

  test "direct uploads are switched off" do
    sign_out :user
    post "/rails/active_storage/direct_uploads", params: { blob: { filename: "x.png", byte_size: 10, checksum: "abc", content_type: "image/png" } }
    assert_response :not_found
  end

  test "a hard-to-read color is saved with a warning shown" do
    patch admin_business_path(tab: "branding"), params: { business: { brand_color: "#facc15" } }
    follow_redirect!
    assert_select "[data-brand-preview-target=warnings] li", /light against a white page/
  end

  test "the dashboard checklist counts an uploaded logo" do
    @business.update!(brand_color: Branding::DEFAULT_COLOR) # a custom colour also counts
    get admin_root_path
    assert_select "a[href=?]", edit_admin_business_path(tab: "branding", from: "setup"), "Add branding"
    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    get admin_root_path
    assert_select "a[href=?]", edit_admin_business_path(tab: "branding", from: "setup"), false
  end

  test "client pages use the logo, or the name wordmark, and show Powered by Shadetree" do
    render_client = -> { ApplicationController.render(html: "Quote", layout: "client", assigns: { business: @business.reload }) }
    html = render_client.call
    assert_includes html, %(class="client-logo" aria-hidden="true">TB</span>)
    assert_match %r{Powered by <span class="wordmark wordmark-small">Shadetree</span>}, html # 13px: one colour
    assert_includes html, "--color-brand: #{@business.branding.color}"

    @business.update!(logo: { io: file_fixture("logo.png").open, filename: "logo.png" })
    html = render_client.call
    assert_match(/<img alt="#{@business.name}" class="client-logo-image" src="[^"]+logo\.png"/, html)
    assert_not_includes html, %(class="client-logo")
  end
end
