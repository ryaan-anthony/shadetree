# INS-02: everything a business has, in zips: every CSV, each quote's and invoice's PDF (drafts
# in their own folder), and every uploaded file (document attachments, job files, visit photos,
# request photos and site photos from following requests up, the logo), with a README explaining the layout. A new part starts when one
# reaches PART_BYTES, so a business with years of photos still gets all of it. Built inside the
# business.
class DataExport::Archive
  PART_BYTES = 1.gigabyte
  MAX_BYTES = 25.gigabytes # checked up front, from the stored files' sizes
  PDF_TRIES = 3

  class TooLarge < StandardError; end

  NOT_INCLUDED = [
    "Your services and prices, tax rates, team (and team profiles) and settings (see them in the app)",
    "Plan and billing history (from your billing emails and the billing page)",
    "Activity timelines and email logs",
    "Your questions to Shadetree support (see them under Help)" # OPS-05
  ].freeze

  # heartbeat: called now and then while writing, so a long build shows it's alive.
  def initialize(business, heartbeat: nil)
    @business = business
    @heartbeat = heartbeat
    @skipped = []
    @written = 0
  end

  # Yields (part number, an IO of that part's zip) as each part is finished; returns how many
  # files they hold.
  def write_parts(&on_part)
    check_size!
    @on_part = on_part
    @part = 0
    start_part
    DataExport::TABLES.each_value { |table| add("csv/#{table.filename}", table.generate.first) }
    Quote.find_each { add_pdf("documents/quotes", _1) }
    Invoice.find_each { add_pdf("documents/invoices", _1) }
    attachments("files/quotes", Quote, :attachments, &:number)
    attachments("files/invoices", Invoice, :attachments, &:number)
    attachments("files/jobs", Job, :attachments, &:number)
    attachments("files/visits", Visit.includes(:job), :photos) { "#{_1.job.number} #{_1.scheduled_on.iso8601}" }
    attachments("files/requests", ServiceRequest, :photos) { "#{_1.created_at.to_date.iso8601} #{_1.uid}" }
    attachments("files/requests", ServiceRequest, :site_photos) { "#{_1.created_at.to_date.iso8601} #{_1.uid} site" } # JOB-06
    add_blob("branding", @business.logo.blob) if @business.logo.attached?
    finish_part(readme: true)
    @written
  end

  private

  def check_size!
    bytes = attachments_scope.joins(:blob).sum("active_storage_blobs.byte_size")
    raise TooLarge, "Your files add up to more than #{MAX_BYTES / 1.gigabyte} GB, too much to put together here." if bytes.to_i > MAX_BYTES
  end

  def attachments_scope
    ids = { "Quote" => Quote, "Invoice" => Invoice, "Job" => Job, "Visit" => Visit, "ServiceRequest" => ServiceRequest }
    ids.map { |type, model| ActiveStorage::Attachment.where(record_type: type, record_id: model.select(:id)) }.reduce(:or)
  end

  def start_part
    @part += 1
    @file = Tempfile.new([ "export-part-#{@part}", ".zip" ], binmode: true)
    @zip = ZipWriter.new(@file)
  end

  # The README goes in the last part, once everything that couldn't be included is known.
  def finish_part(readme: false)
    @zip.add("README.txt", readme_text) if readme
    @zip.finish
    @file.rewind
    @on_part.call(@part, @file)
  ensure
    @file&.close!
  end

  def add(name, data, compress: true, at: Time.current)
    if @zip.size.positive? && @zip.size + data.bytesize > PART_BYTES
      finish_part
      start_part
    end
    @zip.add(name, data, compress:, at:)
    @written += 1
    @heartbeat&.call if (@written % 25).zero?
  end

  def add_pdf(folder, document)
    folder = "#{folder}/drafts" unless document.store_pdf?
    pdf = with_retries { document.current_pdf }
    add("#{folder}/#{safe(document.pdf_filename)}", pdf.respond_to?(:download) ? pdf.download : pdf, compress: false)
  rescue PdfRenderer::Error => error
    @skipped << "#{document.pdf_filename}: the PDF couldn't be made (#{error.message.truncate(80)})"
  end

  def with_retries
    tries = 0
    begin
      yield
    rescue PdfRenderer::Error => error
      raise unless error.message.include?("busy") && (tries += 1) < PDF_TRIES

      sleep 2
      retry
    end
  end

  def attachments(folder, scope, name)
    scope.public_send(:"with_attached_#{name}").find_each do |record|
      record.public_send(name).each { |attachment| add_blob("#{folder}/#{safe(yield(record))}", attachment.blob) }
    end
  end

  def add_blob(folder, blob)
    add("#{folder}/#{safe(blob.filename.to_s)}", blob.download, compress: blob.content_type.to_s.start_with?("text/"), at: blob.created_at)
  rescue ActiveStorage::FileNotFoundError
    @skipped << "#{folder}/#{blob.filename}: the file is missing from storage"
  end

  # A name that's safe in any zip tool: no path separators, no "." or "..", no leading dots, no
  # trailing dots or spaces, and the extension kept when it's shortened.
  def safe(name)
    name = name.to_s.gsub(%r{[/\\\x00-\x1f:*?"<>|]}, "-").squish.sub(/\A\.+/, "").sub(/[. ]+\z/, "")
    extension = File.extname(name).first(10)
    name = "#{File.basename(name, extension).first(110)}#{extension}"
    name.presence || "file"
  end

  def readme_text
    <<~TEXT
      #{@business.name}: everything in Shadetree, exported #{@business.today.iso8601}.
      #{"It's in #{@part} parts (zips); unzip them all into one folder.\n" if @part > 1}
      csv/         Your records as spreadsheets. Money is a plain number in the document's currency;
                   dates are YYYY-MM-DD; times are in #{@business.time_zone.name}.
      documents/   Each quote's and invoice's PDF, as clients see it. Drafts (never sent) are in drafts/.
      files/       Files attached to quotes, invoices and jobs; visit photos; request photos (and
                   site photos from following them up, in each request's "site" folder).
      #{"branding/    Your logo.\n" if @business.logo.attached?}
      Not in this export:
      #{NOT_INCLUDED.map { "  - #{_1}" }.join("\n")}
      #{"\nCouldn't be included:\n#{@skipped.map { "  - #{_1}" }.join("\n")}\n" if @skipped.any?}
    TEXT
  end
end
