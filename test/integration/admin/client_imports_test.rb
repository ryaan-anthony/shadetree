require "test_helper"

# CLI-06: uploading a CSV, matching columns and previewing.
class Admin::ClientImportsTest < ActionDispatch::IntegrationTest
  setup do
    @business = businesses(:one)
    sign_in users(:one)
    post switch_admin_business_path, params: { business: @business.uid }
  end

  def upload(text, name: "clients.csv")
    post admin_client_imports_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: name) }
  end

  test "Owners and Admins import; technicians can't" do
    sign_out :user
    assert_permission_matrix(owner: true, admin: true, technician: false) { get new_admin_client_import_path }
  end

  test "upload, check the guessed columns, change one, and see the preview with problems and duplicates" do
    as_business(@business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
    get admin_clients_path
    assert_select "a[href=?]", new_admin_client_import_path, "Import"

    upload("Full Name,E-mail,Phone,Birthday,Fax\nMaria L,maria@example.com,,1990,\nBo Diaz,,555-010-0200,,\n,,,,\nCal,not-an-email,,,\n", name: "Old CRM export.csv")
    import = as_business(@business) { ClientImport.last }
    assert_redirected_to edit_admin_client_import_path(import)
    assert_equal [ "Old CRM export.csv", 3 ], [ import.filename, import.total_rows ]
    follow_redirect!
    assert_select "#column_0 option[selected]", "Name"
    assert_select "#column_1 option[selected]", "Email"
    assert_select "#column_3 option[selected]", 0
    assert_select "#column_4", 0, "an empty column isn't listed"
    assert_select "#empty-columns", /1 column with nothing in it/
    assert_select "#import-preview tbody tr", 3
    assert_select "#import-preview tr", /5.*Cal/m, "line numbers count the blank line"
    assert_select "#import-preview tr", /Maria L.*Matches Maria Lopez/m
    assert_select "#import-preview tr", /Bo Diaz.*New/m
    assert_select "#import-preview tr", /Cal.*Won't import.*isn't an email/m

    patch admin_client_import_path(import), params: { client_import: { columns: { "0" => "company_name", "1" => "email", "2" => "", "3" => "notes" }, duplicates: "create" } }
    assert_redirected_to edit_admin_client_import_path(import)
    import.reload
    assert_equal({ "0" => "company_name", "1" => "email", "3" => "notes" }, import.mapping)
    assert_equal "create", import.duplicates

    patch admin_client_import_path(import), params: { client_import: { columns: { "0" => "notes", "1" => "notes" } } }
    assert_response :unprocessable_content
    assert_select ".banner", /Notes is chosen for more than one column.*client's name/m
  end

  test "a file that's too big is refused before it's read" do
    big = Rack::Test::UploadedFile.new(StringIO.new("Name\n" + "a" * (ClientImport::CsvFile::MAX_BYTES + 1)), "text/csv", original_filename: "big.csv")
    post admin_client_imports_path, params: { file: big }
    assert_match "larger than", flash[:alert]
    assert_equal 0, as_business(@business) { ClientImport.count }
  end

  test "a file that can't be read says why" do
    upload("")
    assert_redirected_to new_admin_client_import_path
    assert_match "empty", flash[:alert]
    post admin_client_imports_path
    assert_match "Choose a CSV file", flash[:alert]
  end

  test "the template downloads, and imports belong to their business" do
    get template_admin_client_imports_path
    assert_equal "text/csv", response.media_type
    assert_match(/\AName,Company,Email,Phone/, response.body)
    assert_equal({ "0" => "display_name", "1" => "company_name", "2" => "email", "3" => "phone", "4" => "address_line1", "5" => "address_line2",
                   "6" => "city", "7" => "region", "8" => "postal_code", "9" => "notes", "10" => "tags" },
                 ClientImport.auto_map(CSV.parse_line(response.body.lines.first)), "the template maps itself")

    theirs = as_business(businesses(:two)) do
      ClientImport.create!(business: businesses(:two), filename: "x.csv", headers: [ "Name" ], mapping: { "0" => "display_name" })
    end
    assert_not_found_across_businesses { get edit_admin_client_import_path(theirs) }
  end
end
