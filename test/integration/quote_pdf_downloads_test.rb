require "test_helper"

# QTE-02: staff download the PDF from the builder, clients from the client page.
class QuotePdfDownloadsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    @quote = as_business(@business) do
      maria = Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ])
      Quote.start(client: maria).tap { _1.update!(title: "Spring cleanup") }
    end
  end

  def sign_in_staff
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  test "staff download a draft's PDF; technicians can't" do
    sign_in_staff
    with_fake_pdf_renderer do |calls|
      get pdf_admin_quote_path(@quote)
      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_match %(attachment; filename="Quote #{@quote.number}.pdf"), response.headers["Content-Disposition"]
      assert response.body.start_with?("%PDF")
      assert_equal 1, calls.size

      get edit_admin_quote_path(@quote)
      assert_select "a[href=?]", pdf_admin_quote_path(@quote), /Download PDF/
    end
    sign_out :user
    with_fake_pdf_renderer do
      assert_permission_matrix(owner: true, admin: true) { get pdf_admin_quote_path(@quote) }
      as_technician { get pdf_admin_quote_path(@quote) }
      assert_response :not_found, "QTE-07: Technicians reach only their own drafts from requests"
    end
  end

  test "clients download through their link; not for a draft, a revoked link or another business" do
    as_business(@business) { @quote.update_column(:status, "sent") }
    link = as_business(@business) { ClientLink.issue!(@quote) }
    with_fake_pdf_renderer do |calls|
      get client_link_path(link.token)
      assert_select "a[href=?]", client_quote_pdf_path(link.token), /Download PDF/
      2.times do
        get client_quote_pdf_path(link.token)
        assert_response :success
        assert_equal "application/pdf", response.media_type
      end
      assert_equal 1, calls.size, "the stored file is reused"

      as_business(@business) { @quote.update_column(:status, "draft") }
      assert_not_found_across_businesses { get client_quote_pdf_path(link.token) }
      as_business(@business) { @quote.update_column(:status, "sent") }
      as_business(@business) { link.revoke! }
      get client_quote_pdf_path(link.token)
      assert_response :gone
      assert_not_found_across_businesses { get client_quote_pdf_path("1" * ClientLink::TOKEN_LENGTH) }

      sign_in_staff
      other = as_business(businesses(:two)) do
        Quote.start(client: Client.create!(display_name: "Theirs", contact_methods_attributes: [ { kind: "phone", value: "5550100100" } ]))
      end
      assert_not_found_across_businesses { get pdf_admin_quote_path(other) }
    end
  end

  test "if the PDF can't be made, the person is told and sent back" do
    sign_in_staff
    with_fake_pdf_renderer(fail_with: PdfRenderer::Error.new("Chrome timed out")) do
      get pdf_admin_quote_path(@quote)
      assert_redirected_to edit_admin_quote_path(@quote)
      assert_equal "The PDF couldn't be made just now. Please try again in a minute.", flash[:alert]
    end
  end
end
