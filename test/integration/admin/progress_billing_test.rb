require "test_helper"

# PAY-08 (split_jobs flag): progress invoices from a job or a quote before the work is done,
# credited on the final bill; roles and tenancy.
class Admin::ProgressBillingTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @business.update!(auto_create_jobs: false)
    @quote = as_business(@business) do
      client = Client.create!(display_name: "Pat Lee", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      quote = Quote.start(client:, created_by: users(:one))
      quote.title = "Roof"
      quote.sync_line_items([ { "key" => "r", "name" => "Roof", "quantity" => "1", "unit_price" => "1000" } ])
      quote.save!
      quote.update_columns(status: "approved")
      quote
    end
    enable_feature(:split_jobs)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def make = as_business(@business) { Job.from_quote!(@quote.reload, picks: { @quote.line_items.sole.id => "1" }) }

  test "a progress invoice from an open job, lowered, then credited on the job's final invoice" do
    job = make
    post admin_job_invoices_path(job, progress: 1)
    invoice = as_business(@business) { Invoice.last }
    assert_redirected_to edit_admin_invoice_path(invoice)
    assert_equal "Progress invoice #{invoice.number} started from job #{job.number}.", flash[:notice]
    assert_equal [ "progress", 1000_00 ], [ invoice.kind, invoice.total_cents ]

    line = as_business(@business) { invoice.line_items.sole }
    patch admin_invoice_path(invoice), params: { invoice: { lines_present: "1", lines: { "0" => { key: line.key, name: "Roof", quantity: "1", unit_price: "1200" } } } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_match "Roof: only $1,000.00 is left to bill.", response.body

    as_business(@business) do
      invoice.reload.line_items.sole.update!(unit_price: "400")
      invoice.reload.save!
      invoice.mark_sent!(by: users(:one), channel: "link")
      job.reload.complete!(by: users(:one))
    end
    post admin_job_invoices_path(job)
    final = as_business(@business) { Invoice.last }
    assert_equal [ "work", 600_00 ], [ final.kind, final.total_cents ]
  end

  test "a quote's progress invoice bills what isn't done; with nothing left it's refused, saying why" do
    post admin_quote_invoices_path(@quote, progress: 1)
    invoice = as_business(@business) { Invoice.last }
    assert_equal [ "progress", @quote.id, 1000_00 ], [ invoice.kind, invoice.quote_id, invoice.total_cents ]
    post admin_quote_invoices_path(@quote, progress: 1)
    assert_redirected_to admin_quote_path(@quote)
    assert_equal "Couldn't start an invoice: Nothing on #{@quote.number} is left to bill as progress.", flash[:alert]
  end

  test "technicians can't bill progress" do
    job = make
    assert_permission_matrix(owner: true, admin: true, technician: false) { post admin_job_invoices_path(job, progress: 1) }
    assert_permission_matrix(technician: false) { post admin_quote_invoices_path(@quote, progress: 1) }
  end

  test "another business's jobs and quotes aren't found for progress billing" do
    theirs = as_business(businesses(:two)) do
      client = Client.create!(display_name: "Zed", contact_methods_attributes: [ { kind: "phone", value: "5550100199" } ])
      Job.create!(client:, title: "Theirs")
    end
    assert_not_found_across_businesses { post admin_job_invoices_path(theirs, progress: 1) }
    their_quote = as_business(businesses(:two)) { Quote.create!(client: theirs.client, title: "Theirs") }
    assert_not_found_across_businesses { post admin_quote_invoices_path(their_quote, progress: 1) }
  end
end
