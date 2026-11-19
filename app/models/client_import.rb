# CLI-06: bringing a client list over from a CSV. Upload → map columns (guessed from the
# headers, changeable) and choose what to do with likely duplicates, with a preview → import in
# the background → a summary, a report of rows that didn't go in, and undo for UNDO_WINDOW.
#
# Each row becomes one client: a name (or first + last name, or the company), company, any
# number of email and phone columns, one address (the billing property), notes and tags.
class ClientImport < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[mapping queued importing finished failed undone].freeze
  DUPLICATES = { "skip" => "Skip them", "create" => "Add them anyway" }.freeze
  PREVIEW_ROWS = 10
  UNDO_WINDOW = 7.days
  MAX_PROBLEMS = 1_000 # rows kept for the report; counts are always complete

  # Client fields a column can map to. Email and phone may be mapped from several columns.
  FIELDS = {
    "display_name" => "Name", "first_name" => "First name", "last_name" => "Last name", "company_name" => "Company",
    "email" => "Email", "phone" => "Phone",
    "address_line1" => "Street address", "address_line2" => "Address line 2", "city" => "City",
    "region" => "State / province", "postal_code" => "ZIP / postal code",
    "notes" => "Notes", "tags" => "Tags"
  }.freeze
  REPEATABLE = %w[email phone].freeze

  # Header spellings, compared lowercased with only letters and digits.
  SYNONYMS = {
    "display_name" => %w[name fullname clientname customername customer client contactname displayname contact],
    "first_name" => %w[firstname first givenname fname],
    "last_name" => %w[lastname last surname familyname lname],
    "company_name" => %w[company companyname business businessname organization organisation org],
    "email" => %w[email emailaddress mail email1 email2 primaryemail workemail homeemail],
    "phone" => %w[phone phonenumber telephone tel mobile mobilephone cell cellphone homephone workphone primaryphone phone1 phone2],
    "address_line1" => %w[address street streetaddress address1 addressline1 serviceaddress billingaddress],
    "address_line2" => %w[address2 addressline2 unit apt suite],
    "city" => %w[city town],
    "region" => %w[state province region county stateprovince],
    "postal_code" => %w[zip zipcode postcode postalcode postal],
    "notes" => %w[notes note comments comment description],
    "tags" => %w[tags tag labels label groups group]
  }.freeze

  belongs_to :created_by, class_name: "User", optional: true
  has_many :clients, dependent: :nullify
  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validates :duplicates, inclusion: { in: DUPLICATES.keys }
  validate :mapping_makes_sense, if: -> { mapping_changed? && !new_record? }

  STATUSES.each { |status| define_method(:"#{status}?") { self.status == status } }

  # A new import from an uploaded file, with columns mapped from the headers. Raises
  # CsvFile::Invalid with a reason to show.
  def self.start!(upload, by:)
    data = upload.read
    csv = CsvFile.read(data)
    create!(created_by: by, filename: upload.original_filename.to_s.first(200).presence || "clients.csv",
            headers: csv.headers, mapping: auto_map(csv.headers), total_rows: csv.rows.size,
            file: { io: StringIO.new(data), filename: "clients.csv", content_type: "text/csv" })
  end

  # { column index (string) => field }, guessed from header names; each field once (but email
  # and phone from every matching column).
  def self.auto_map(headers)
    taken = []
    headers.each_with_index.each_with_object({}) do |(header, index), mapping|
      key = header.to_s.downcase.gsub(/[^a-z0-9]/, "")
      field = SYNONYMS.find { |_, names| names.include?(key) }&.first
      field ||= "email" if key.include?("email")
      field ||= "phone" if key.match?(/phone|mobile|cell/)
      next unless field && (REPEATABLE.include?(field) || !taken.include?(field))

      taken << field
      mapping[index.to_s] = field
    end
  end

  def rows = @rows ||= CsvFile.read(file.download).rows

  def field_for(index) = mapping[index.to_s]

  # The client a row would become (unsaved), for the preview and the import.
  def build_client(row)
    values = Hash.new { |hash, key| hash[key] = [] }
    mapping.each { |index, field| values[field] << row[index.to_i].to_s.strip if row[index.to_i].present? }
    one = ->(field) { values[field].join(" ").squish.presence }

    name = one.("display_name") || [ one.("first_name"), one.("last_name") ].compact.join(" ").presence || one.("company_name") || values["email"].first
    contact = values["email"].flat_map { _1.split(/[;,\s]+/) }.compact_blank.map { { kind: "email", value: _1 } } +
              values["phone"].flat_map { _1.split(/[;\n]+/) }.map(&:strip).compact_blank.map { { kind: "phone", value: _1 } }
    address = %w[address_line1 address_line2 city region postal_code].index_with { one.(_1) }

    Client.new(display_name: name, company_name: one.("company_name"), notes: values["notes"].join("\n").presence,
               tag_list: values["tags"].join(","), client_import: self,
               contact_methods_attributes: contact.uniq.first(10).each_with_index.map { |method, position| method.merge(position:) },
               properties_attributes: address["address_line1"] ? [ address.merge(billing: true, country: business.country) ] : [])
  end

  # Existing clients this one may duplicate (same email or phone).
  def duplicates_of(client)
    Client.matching(emails: client.contact_methods.select(&:email?).map(&:value), phones: client.contact_methods.select(&:phone?).map(&:value))
  end

  # The first rows as they'll be imported: [row number, client, problems, duplicates].
  def preview
    rows.first(PREVIEW_ROWS).each_with_index.map do |row, index|
      client = build_client(row)
      [ index + 2, client, problems_for(client), duplicates_of(client).to_a ] # row 1 is the header
    end
  end

  def mapped_fields = mapping.values

  # Why a row's client can't be saved, in words about the row ("“bad-email” isn't an email
  # address"), or [] if it can.
  def problems_for(client)
    return [] if client.valid?

    nested = client.contact_methods.reject { _1.errors.empty? }.map { |method| "“#{method.value}” #{method.errors[:value].first || method.errors.full_messages.first}" }
    nested += client.properties.reject { _1.errors.empty? }.map { |property| "Address: #{property.errors.full_messages.to_sentence}" }
    own = client.errors.reject { _1.attribute.to_s.start_with?("contact_methods", "properties") }.map(&:full_message)
    own.map { _1.sub(/\ADisplay name can't be blank\z/, "No name, company or email") } + nested
  end

  private

  def mapping_makes_sense
    unknown = mapping.values - FIELDS.keys
    errors.add(:mapping, "has unknown fields: #{unknown.join(", ")}") if unknown.any?
    doubled = (mapping.values - REPEATABLE).tally.select { _2 > 1 }.keys
    errors.add(:base, "#{doubled.map { FIELDS[_1] }.to_sentence} #{doubled.one? ? "is" : "are"} chosen for more than one column.") if doubled.any?
    unless mapping.values.intersect?(%w[display_name first_name last_name company_name email])
      errors.add(:base, "Choose which column has the client's name (or company, or email).")
    end
  end
end
