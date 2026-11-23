require "test_helper"

# PLT-18: one format per data type, and the copy that joins strings. The page-wide checks (a
# dash for a zero, Stripe IDs, phones, relative times in tables) are in design_system_test.rb.
class Admin::FormattingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    @pages = StaffPages.build(@business, @owner)
  end

  def page_text(key)
    get StaffPages.find(@pages, key).path
    assert_response :success
    Nokogiri::HTML5(response.body).at_css("main").text.squish
  end

  test "joined strings keep their spaces in the page's text" do
    assert_match(/Paid in all: \$\d/, page_text(:client))

    quote = Tenancy.with_business(@business) { Quote.find_by!(title: "Spring cleanup") }
    email = Tenancy.with_business(@business) do
      EmailMessage.create!(kind: "quote_sent", to: "maria-lopez@example.com", related: quote, status: "failed", error: "The mail server refused the email")
    end
    Tenancy.with_business(@business) { quote.mark_sent!(by: @owner, channel: "email", recipient: email.to, email_message: email) }
    text = page_text(:quote_sent)
    assert_match(/Emailed to maria-lopez@example\.com \w{3} \d+, \d{4}, \d+:\d\d [AP]M by #{@owner.full_name}/, text)
    assert_match(/Couldn't send \(The mail server refused the email\)/, text)
  end

  test "a line's quantity is written under its name, as on invoices" do
    assert_match(/Gutter cleaning 1 visit × \$120\.00 \$120\.00/, page_text(:job))
    assert_match(/Window cleaning 1 visit × \$120\.00 \$120\.00/, page_text(:invoice_sent))
    assert_match(/Gutter cleaning 1 visit × \$120\.00/, page_text(:my_visit))
    assert_match(/Gutter cleaning 1 visit × \$120\.00/, page_text(:new_visit))
  end

  test "zero is $0.00 in the lists; a void invoice's balance is a dash" do
    get admin_jobs_path
    assert_select "tr", text: /Estimate visit/ do
      assert_select "td.money", "$0.00"
    end
    get admin_invoices_path
    assert_select "tr", text: /Edging/ do
      assert_select "td.money", count: 2, text: /\$/
      assert_select "td.money", "$0.00"
    end
    assert_select "tr", text: /Lights/ do
      assert_select "td.money", "—"
    end
  end

  test "Stripe's reference is labelled in the invoice's Payments card, and kept off the job page and the timeline" do
    assert_match(/Stripe reference: pi_staffPages0001/, page_text(:invoice_paid))
    assert_no_match(/pi_staffPages0001/, page_text(:job_paid))
    assert_no_match(/pi_staffPages0001/, page_text(:client))
  end

  test "copy: the arrival note names the zone once, and pagination is one weight" do
    assert_match(/Times in Eastern Time \(US & Canada\)\./, page_text(:new_visit))
    get admin_jobs_path
    assert_select ".pagination p .font-semibold", 0
  end
end
