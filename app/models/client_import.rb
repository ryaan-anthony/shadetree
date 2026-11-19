require "csv"

# CLI-06: bringing a client list over from a CSV. Upload → map columns (guessed from the
# headers, changeable) and choose what to do with likely duplicates, with a preview → import in
# the background → a summary, a report of rows that didn't go in, and undo for UNDO_WINDOW.
#
# Each row becomes one client: a name (or first + last name, or the company), company, any
# number of email and phone columns, one address (the billing property), notes and tags.
class ClientImport < ApplicationRecord
  include BusinessOwned

  STATUSES = %w[mapping queued importing finished failed undoing undone].freeze
  PROGRESS_EVERY = 25 # rows between progress updates
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

  # Header spellings, after header_key (lowercased, prefixes like "Home"/"Billing" and suffixes
  # like "1 - Value" removed, letters and digits only).
  SYNONYMS = {
    "display_name" => %w[name fullname displayname clientname customername customer client contactname contact],
    "first_name" => %w[firstname first givenname fname],
    "last_name" => %w[lastname last surname familyname lname],
    "company_name" => %w[company companyname business businessname organization organisation organizationname org],
    "email" => %w[email emails emailaddress mail],
    "phone" => %w[phone phonenumber phones telephone tel mobile mobilephone mobilenumber cell cellphone number],
    "address_line1" => %w[address street streetaddress addressline street1 address1 addressline1],
    "address_line2" => %w[address2 addressline2 street2 unit apt suite],
    "city" => %w[city town],
    "region" => %w[state province region county stateprovince],
    "postal_code" => %w[zip zipcode postcode postalcode postal],
    "notes" => %w[notes note comments comment description],
    "tags" => %w[tags tag labels label groups group categories]
  }.freeze
  # Columns about another column, never data to import: "E-mail 1 - Label", "E-mail Type",
  # "E-mail Display Name", "Phonetic First Name", "Address 1 - Formatted".
  IGNORED_HEADER = /\b(label|type|formatted|phonetic|country|fax|pager|assistant'?s?|car|radio|tty|telex|callback|yomi)\b|.\s*display ?name/
  HEADER_PREFIXES = /\A(home|business|work|billing|service|primary|main|other|personal|default|property)\s+/

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
    raise CsvFile::Invalid, "The file is larger than #{CsvFile::MAX_BYTES / 1.megabyte} MB. Split it into smaller files." if upload.size > CsvFile::MAX_BYTES

    data = upload.read
    csv = CsvFile.read(data)
    examples = csv.headers.each_index.map { |index| csv.rows.lazy.map { _1[index] }.find(&:present?).to_s.first(80) }
    create!(created_by: by, filename: upload.original_filename.to_s.first(200).presence || "clients.csv",
            headers: csv.headers, examples:, mapping: auto_map(csv.headers, examples:), total_rows: csv.rows.size,
            preview_rows: csv.line_numbers.zip(csv.rows).first(PREVIEW_ROWS),
            file: { io: StringIO.new(data), filename: "clients.csv", content_type: "text/csv" })
  end

  # { column index (string) => field }, guessed from header names; each field once (but email
  # and phone from every matching column). Columns empty in every row aren't mapped.
  def self.auto_map(headers, examples: nil)
    taken = []
    headers.each_with_index.each_with_object({}) do |(header, index), mapping|
      next if examples && examples[index].blank?

      field = guess_field(header)
      next unless field && (REPEATABLE.include?(field) || !taken.include?(field))

      taken << field
      mapping[index.to_s] = field
    end
  end

  def self.guess_field(header)
    text = header.to_s.downcase.squish
    return if text.match?(IGNORED_HEADER)

    text = text.sub(/\s*-\s*(value|name)\z/, " \\1").sub(/\s*#s?\z/, "") # "E-mail 1 - Value", "Main Phone #s"
    text = text.gsub(/\b(address|organization|e-mail|email|phone)\s+\d+\s*-\s*/, "") # "Address 1 - Street", "Organization 1 - Name"
    text = text.gsub(/(street|address|line)\s*2\b/, "\\1two").gsub(/\s*\d+\b/, "").gsub("two", " 2") # keep "Street 2", drop "Phone 1"
    text = text.sub(HEADER_PREFIXES, "") unless text.match?(/\A(business|work|home)\s*\z/)
    key = text.gsub(/[^a-z0-9]/, "")
    key = "organizationname" if key == "name" && header.to_s.downcase.include?("organization")
    SYNONYMS.find { |_, names| names.include?(key) }&.first ||
      ("email" if text.match?(/\be-?mail\b/)) ||
      ("phone" if text.match?(/\b(phone|mobile|cell)\b/))
  end

  def csv_file = @csv_file ||= CsvFile.read(file.download)
  def rows = csv_file.rows

  # "Imported 120 clients from clients.csv; 3 skipped, 2 couldn't be added."
  def summary
    return "Your import of #{filename} stopped partway. #{created_count} clients were added." if failed?

    parts = [ ("#{skipped_count} skipped" if skipped_count.positive?), ("#{failed_count} couldn't be added" if failed_count.positive?) ].compact
    "Imported #{created_count} #{created_count == 1 ? "client" : "clients"} from #{filename}#{"; #{parts.join(", ")}" if parts.any?}."
  end

  def field_for(index) = mapping[index.to_s]

  # The client a row would become (unsaved), for the preview and the import.
  def build_client(row)
    values = Hash.new { |hash, key| hash[key] = [] }
    mapping.each { |index, field| values[field] << row[index.to_i].to_s.strip if row[index.to_i].present? }
    one = ->(field) { values[field].join(" ").squish.presence }

    name = one.("display_name") || [ one.("first_name"), one.("last_name") ].compact.join(" ").presence || one.("company_name") || values["email"].first
    contact = values["email"].flat_map { _1.split(/[;,\s]+/) }.compact_blank.map { { kind: "email", value: _1 } } +
              values["phone"].flat_map { _1.split(/[;,\n]+|:::/) }.map(&:strip).compact_blank.map { { kind: "phone", value: _1 } }
    address = %w[address_line1 address_line2 city region postal_code].index_with { one.(_1) }

    Client.new(display_name: name, company_name: one.("company_name"), notes: values["notes"].join("\n").presence,
               tag_list: values["tags"].flat_map { _1.split(/,|:::/) }.map(&:strip).reject { _1.start_with?("*") }.join(","), client_import: self,
               contact_methods_attributes: contact.uniq.first(10).each_with_index.map { |method, position| method.merge(position:) },
               properties_attributes: address["address_line1"] ? [ address.merge(billing: true, country: business.country) ] : [])
  end

  # Existing clients this one may duplicate (same email or phone).
  def duplicates_of(client)
    Client.matching(emails: client.contact_methods.select(&:email?).map(&:value), phones: client.contact_methods.select(&:phone?).map(&:value))
  end

  # The first rows as they'll be imported: [line number, client, problems, duplicates].
  def preview
    preview_rows.map do |line, row|
      client = build_client(row)
      [ line, client, problems_for(client), duplicates_of(client).to_a ]
    end
  end

  def mapped_fields = mapping.values

  def running? = queued? || importing? || undoing?
  def done? = finished? || failed?
  def started_by?(user) = created_by_id == user&.id

  # Queues the import (once).
  def start!
    with_lock do
      return false unless mapping?

      update!(status: "queued")
    end
    ClientImportJob.perform_later(id, business_id)
    true
  end

  # Imports every row: a client per row, skipping likely duplicates if chosen, and recording why
  # a row didn't go in. Runs in ClientImportJob, inside the business.
  def run!
    update!(status: "importing", started_at: Time.current, processed_rows: 0, created_count: 0, skipped_count: 0, failed_count: 0, problems: [])
    csv_file.rows.each_with_index do |row, index|
      import_row(row, csv_file.line_numbers[index])
      update_columns(processed_rows: index + 1, created_count:, skipped_count:, failed_count:, updated_at: Time.current) if ((index + 1) % PROGRESS_EVERY).zero?
    end
    finish!("finished")
  rescue StandardError => error
    Rails.error.report(error, context: { client_import: id })
    finish!("failed")
  end

  # Clients this import created that can still be removed: no quotes, requests, jobs or invoices.
  def undoable? = finished? && finished_at && finished_at > UNDO_WINDOW.ago && created_count.positive?

  def undo_until = finished_at && finished_at + UNDO_WINDOW

  # Queues removing what it created (once).
  def undo!
    with_lock do
      return false unless undoable?

      update!(status: "undoing")
    end
    ClientImportUndoJob.perform_later(id, business_id)
    true
  end

  # Removes the clients it created that have no documents yet; others are kept and counted.
  def run_undo!
    removed = 0
    clients.find_each do |client|
      next if client.documents?

      client.destroy!
      removed += 1
    end
    update!(status: "undone", undone_at: Time.current, undone_count: removed)
  end

  # The report of rows that didn't go in: row number, why, then the row as uploaded. Cells that
  # a spreadsheet would run as a formula are prefixed with ', so opening the report is safe.
  def report_csv
    CSV.generate do |csv|
      csv << [ "Row", "Why", *headers ].map { safe_cell(_1) }
      problems.each { |problem| csv << [ problem["row"], problem["reason"], *problem["values"] ].map { safe_cell(_1) } }
    end
  end

  # Why a row's client can't be saved, in words about the row ("“bad-email” isn't an email
  # address"), or [] if it can.
  def problems_for(client)
    return [] if client.valid?

    nested = client.contact_methods.reject { _1.errors.empty? }.map { |method| "“#{method.value.truncate(60)}” #{method.errors[:value].first || method.errors.full_messages.first}" }
    nested += client.properties.reject { _1.errors.empty? }.map { |property| "Address: #{property.errors.full_messages.to_sentence}" }
    own = client.errors.reject { _1.attribute.to_s.start_with?("contact_methods", "properties") }.map(&:full_message)
    own.map { _1.sub(/\ADisplay name can't be blank\z/, "No name, company or email") } + nested
  end

  private

  def import_row(row, number)
    client = build_client(row)
    if (problems = problems_for(client)).any?
      self.failed_count += 1
      note_problem(number, problems.to_sentence, row)
    elsif duplicates == "skip" && (existing = duplicates_of(client).first)
      self.skipped_count += 1
      note_problem(number, "Skipped: matches #{existing.display_name}, a client you already have", row)
    else
      client.save!
      self.created_count += 1
    end
  rescue ActiveRecord::RecordInvalid => error
    self.failed_count += 1
    note_problem(number, error.record.errors.full_messages.to_sentence, row)
  end

  def note_problem(number, reason, row)
    problems << { "row" => number, "reason" => reason, "values" => row } if problems.size < MAX_PROBLEMS
  end

  def finish!(status)
    update!(status:, finished_at: Time.current, processed_rows: status == "finished" ? total_rows : processed_rows)
    file.purge_later # the rows that didn't go in are kept in problems, for the report
    created_by && NotificationType.deliver("client_import_finished", business:, to: [ created_by ], subject: self,
                                           title: summary, path: Rails.application.routes.url_helpers.admin_client_import_path(self))
  end

  def safe_cell(value) = value.to_s.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value

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
