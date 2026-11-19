require "test_helper"

# CLI-06: reading CSVs, guessing columns, and turning rows into clients.
class ClientImportTest < ActiveSupport::TestCase
  Csv = ClientImport::CsvFile

  test "UTF-8 with or without a BOM, UTF-16 and Windows-1252; commas, semicolons and tabs" do
    plain = "Name,Email\nRenée Côté,renee@example.com\n"
    assert_equal [ "Renée Côté", "renee@example.com" ], Csv.read(plain).rows.first
    assert_equal [ "Name", "Email" ], Csv.read("\xEF\xBB\xBF#{plain}").headers
    assert_equal "Renée Côté", Csv.read("\xFF\xFE".b + plain.encode("UTF-16LE").b).rows.first.first
    assert_equal "Renée Côté", Csv.read(plain.encode("Windows-1252").b).rows.first.first
    assert_equal [ "Ana", "ana@example.com" ], Csv.read("Name;Email\r\nAna;ana@example.com\r\n").rows.first
    assert_equal [ "Ana", "ana@example.com" ], Csv.read("Name\tEmail\nAna\tana@example.com\n").rows.first
  end

  test "blank rows are dropped, short rows padded, unnamed columns named" do
    csv = Csv.read("Name,,Phone\n\nAna\n,,\nBo,x,555\n")
    assert_equal [ "Name", "Column 2", "Phone" ], csv.headers
    assert_equal [ [ "Ana", "", "" ], [ "Bo", "x", "555" ] ], csv.rows
  end

  test "empty, header-only, too big, too many rows and binary files say why" do
    { "" => /empty/, "Name,Email\n" => /no clients/, "\x00\x01PK".b => /doesn't look like a CSV/,
      "Name\n\"unclosed\n" => /couldn't be read as CSV/ }.each do |data, message|
      assert_raises(Csv::Invalid, data.inspect) { Csv.read(data) }.then { assert_match message, _1.message }
    end
    assert_match "limit is #{Csv::MAX_ROWS}", assert_raises(Csv::Invalid) { Csv.read("Name\n" + "a\n" * (Csv::MAX_ROWS + 1)) }.message
    assert_match "larger than", assert_raises(Csv::Invalid) { Csv.read("Name\n" + "a" * Csv::MAX_BYTES) }.message
  end

  test "columns are guessed from common header names" do
    headers = [ "First Name", "Last Name", "E-mail Address", "Mobile Phone", "Home Phone", "Street", "Town", "State", "Zip Code", "Comments", "Labels", "Birthday", "Company" ]
    assert_equal({ "0" => "first_name", "1" => "last_name", "2" => "email", "3" => "phone", "4" => "phone", "5" => "address_line1",
                   "6" => "city", "7" => "region", "8" => "postal_code", "9" => "notes", "10" => "tags", "12" => "company_name" },
                 ClientImport.auto_map(headers))
    assert_equal({ "0" => "display_name" }, ClientImport.auto_map(%w[Name Customer]), "a field is guessed once")
  end

  test "a row becomes a client with its contacts, billing address in the business's country, notes and tags" do
    as_business(businesses(:one)) do
      import = ClientImport.new(business: businesses(:one), headers: [], mapping: { "0" => "first_name", "1" => "last_name", "2" => "email", "3" => "phone", "4" => "phone",
                                                                                     "5" => "address_line1", "6" => "city", "7" => "tags", "8" => "notes" })
      client = import.build_client([ "Ana", "Silva", "ana@example.com; ana@work.example", "555-010-0100", "", "1 Elm St", "Asheville", "weekly, VIP", "Gate code 4411" ])
      assert client.valid?, client.errors.full_messages.to_sentence
      assert_equal "Ana Silva", client.display_name
      assert_equal [ "ana@example.com", "ana@work.example", "555-010-0100" ], client.contact_methods.map(&:value)
      assert_equal [ "1 Elm St", "Asheville", businesses(:one).country, true ], client.properties.first.slice(:address_line1, :city, :country, :billing).values
      assert_equal %w[weekly vip], client.tags
      assert_equal "Gate code 4411", client.notes

      company_only = import.tap { _1.mapping = { "0" => "company_name", "1" => "email" } }.build_client([ "Acme Co", "" ])
      assert_equal [ "Acme Co", "Acme Co" ], [ company_only.display_name, company_only.company_name ]
      assert_not import.build_client([ "", "" ]).valid?, "no name at all"
    end
  end

  test "likely duplicates are existing clients with the same email or phone" do
    as_business(businesses(:one)) do
      existing = Client.create!(display_name: "Maria", contact_methods_attributes: [ { kind: "phone", value: "(555) 010-0100" } ])
      import = ClientImport.new(business: businesses(:one), mapping: { "0" => "display_name", "1" => "phone" })
      assert_equal [ existing ], import.duplicates_of(import.build_client([ "M. Lopez", "555.010.0100" ])).to_a
      assert_empty import.duplicates_of(import.build_client([ "Bo", "555 010 9999" ]))
    end
  end
end
