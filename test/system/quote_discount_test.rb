require "application_system_test_case"

# PAY-08 (owner, 2026-11-23): billing part of a quote with a discount asks how much of it to apply
# now. Enter in the create dialog's field sends the amount typed; "Apply all" applies all it can,
# in the dialog and in the builder (which saves it as if typed).
class QuoteDiscountSystemTest < ApplicationSystemTestCase
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    @deck, @steps = Tenancy.with_business(@business) do
      @business.update!(auto_create_jobs: false)
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: @owner)
      quote.set_discount("amount", "300")
      quote.sync_line_items([ { "key" => "d", "name" => "Deck", "quantity" => "1", "unit_price" => "1000" },
                              { "key" => "s", "name" => "Steps", "quantity" => "1", "unit_price" => "100" } ])
      quote.save!
      quote.update_columns(status: "approved")
      quote.line_items.map { |line| Job.from_quote!(quote.reload, picks: { line.id => "1" }) }.tap { _1.first.complete!(by: @owner) }
    end
    visit new_user_session_path
    sign_in_with_form(@owner.email)
    assert_text "Home"
  end

  def applied = Tenancy.with_business(@business) { Invoice.where(kind: "work").last&.quote_discount_share_cents }

  # Waits till the builder's autosave has saved this choice.
  def saved(invoice, cents)
    Timeout.timeout(Capybara.default_max_wait_time * 3) { sleep 0.1 until Tenancy.with_business(@business) { invoice.reload.quote_discount_chosen_cents } == cents }
  end

  test "Enter in the create dialog's field sends the amount typed" do
    visit admin_job_path(@deck)
    find("#job-banner-invoice").click
    within("#job-banner-invoice-dialog") do
      assert_text "Quote discount: $300.00 left. Apply now"
      fill_in "job-banner-invoice-discount", with: "250"
      find_field("job-banner-invoice-discount").send_keys(:enter)
    end
    assert_selector "#quote_discount_field"
    assert_equal 250_00, applied
  end

  test "Apply all in the create dialog, and in the builder" do
    visit admin_job_path(@deck)
    find("#job-banner-invoice").click
    within("#job-banner-invoice-dialog") { click_on "Apply all" }
    assert_selector "#quote_discount_field"
    assert_equal 300_00, applied

    invoice = Tenancy.with_business(@business) { Invoice.where(kind: "work").last }
    Tenancy.with_business(@business) { invoice.update!(quote_discount_applied: "0") }
    visit edit_admin_invoice_path(invoice)
    assert_field "invoice_quote_discount_applied", with: "200.00" # the minimum: only $100 of work is left
    within("#quote_discount_field") { click_on "Apply all" }
    assert_field "invoice_quote_discount_applied", with: "300.00"
    assert_equal 300_00, applied
  end

  test "the dialog's buttons read and tab in the order shown; a clamped amount keeps the builder field focused" do
    visit admin_job_path(@deck)
    find("#job-banner-invoice").click
    within("#job-banner-invoice-dialog") do
      assert_equal [ "Cancel", "Apply all", "Create invoice" ], all("form button").map(&:text)
      find_field("job-banner-invoice-discount").send_keys(:tab)
    end
    assert_equal "Cancel", page.evaluate_script("document.activeElement.textContent.trim()")

    invoice = Tenancy.with_business(@business) { Invoice.from_job!(@deck.reload, by: @owner) }
    visit edit_admin_invoice_path(invoice)
    field = find_field("invoice_quote_discount_applied")
    field.fill_in(with: "50")
    saved(invoice, 50_00) # held to the $200 minimum
    assert_field "invoice_quote_discount_applied", with: "50" # not rewritten under the caret
    assert_equal "invoice_quote_discount_applied", page.evaluate_script("document.activeElement.id"), "still focused"
    field.send_keys(:tab)
    assert_field "invoice_quote_discount_applied", with: "200.00" # what applies, once it's left
  end

  test "typing in the builder's field across an autosave keeps what's typed" do
    invoice = Tenancy.with_business(@business) { Invoice.from_job!(@deck.reload, by: @owner) }
    visit edit_admin_invoice_path(invoice)
    field = find_field("invoice_quote_discount_applied")
    field.click
    field.send_keys([ :control, "a" ], "2")
    saved(invoice, 2_00) # saved in the pause, held to the $200 minimum
    field.send_keys("50")
    assert_field "invoice_quote_discount_applied", with: "250"
    field.send_keys(:tab)
    assert_field "invoice_quote_discount_applied", with: "250.00"
    assert_equal 250_00, Tenancy.with_business(@business) { invoice.reload.quote_discount_share_cents }
  end

  test "the create dialog's field: focused on open, empty with a 0.00 placeholder, and a click then typing gives what's typed" do
    visit admin_job_path(@deck)
    find("#job-banner-invoice").click
    within("#job-banner-invoice-dialog") do
      assert_equal "job-banner-invoice-discount", page.evaluate_script("document.activeElement.id"), "focus lands in the field"
      field = find_field("job-banner-invoice-discount", with: "")
      assert_equal "0.00", field[:placeholder]
      field.click
      field.send_keys("250")
      assert_field "job-banner-invoice-discount", with: "250"
      field.send_keys(:enter)
    end
    assert_selector "#quote_discount_field"
    assert_equal 250_00, applied
  end
end
