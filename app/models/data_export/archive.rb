# INS-02: everything a business has, in one zip: every CSV, each quote's and invoice's PDF, and
# every uploaded file (document attachments, job files, visit photos, request photos, the
# logo), with a README explaining the layout. Built inside the business.
class DataExport::Archive
  MAX_BYTES = 2.gigabytes

  class TooLarge < StandardError; end

  def initialize(business)
    @business = business
    @skipped = []
  end

  # Writes the zip to io; returns how many files it holds.
  def write(io)
    count = 0
    ZipWriter.open(io) do |zip|
      @zip = zip
      DataExport::TABLES.each_value { |table| add("csv/#{table.filename}", table.generate.first) && count += 1 }
      Quote.find_each { |quote| count += 1 if add_pdf("documents/quotes", quote) }
      Invoice.find_each { |invoice| count += 1 if add_pdf("documents/invoices", invoice) }
      count += attachments("files/quotes", Quote, :attachments, &:number)
      count += attachments("files/invoices", Invoice, :attachments, &:number)
      count += attachments("files/jobs", Job, :attachments, &:number)
      count += attachments("files/visits", Visit.includes(:job), :photos) { "#{_1.job.number} #{_1.scheduled_on.iso8601}" }
      count += attachments("files/requests", ServiceRequest, :photos) { "#{_1.created_at.to_date.iso8601} #{_1.uid}" }
      count += 1 if @business.logo.attached? && add_blob("branding", @business.logo.blob)
      add("README.txt", readme, compress: true)
    end
    count
  end

  private

  def add(name, data, compress: true)
    raise TooLarge, "Your data is larger than #{MAX_BYTES / 1.gigabyte} GB, too big for one download." if @zip.size + data.bytesize > MAX_BYTES

    @zip.add(name, data, compress:)
  end

  def add_pdf(folder, document)
    pdf = document.current_pdf
    data = pdf.respond_to?(:download) ? pdf.download : pdf
    add("#{folder}/#{safe(document.pdf_filename)}", data, compress: false)
  rescue PdfRenderer::Error => error
    @skipped << "#{document.pdf_filename}: the PDF couldn't be made (#{error.message.truncate(80)})"
    nil
  end

  def attachments(folder, scope, name)
    count = 0
    scope.public_send(:"with_attached_#{name}").find_each do |record|
      record.public_send(name).each { |attachment| count += 1 if add_blob("#{folder}/#{safe(yield(record))}", attachment.blob) }
    end
    count
  end

  def add_blob(folder, blob)
    add("#{folder}/#{safe(blob.filename.to_s)}", blob.download, compress: blob.content_type.to_s.start_with?("text/"))
  rescue ActiveStorage::FileNotFoundError
    @skipped << "#{folder}/#{blob.filename}: the file is missing from storage"
    nil
  end

  def safe(name) = name.to_s.gsub(%r{[/\\\x00-\x1f:*?"<>|]}, "-").squish.first(120).presence || "file"

  def readme
    <<~TEXT
      #{@business.name}: everything in Shadetree, exported #{@business.today.iso8601}.

      csv/         Your records as spreadsheets. Money is a plain number in the document's currency;
                   dates are YYYY-MM-DD; times are in #{@business.time_zone.name}.
      documents/   Each quote's and invoice's PDF, as clients see it.
      files/       Files attached to quotes, invoices and jobs; visit photos; request photos.
      branding/    Your logo.
      #{"\nNot included:\n#{@skipped.map { "  - #{_1}" }.join("\n")}\n" if @skipped.any?}
    TEXT
  end
end
