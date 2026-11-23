# Files a client sees with a document (quotes QTE-01, invoices PAY-01): photos, re-encoded
# without their metadata (phone photos carry GPS), and PDFs kept as they are if they really are
# PDFs. Problems are added as errors on save. Photos get a page-sized version at upload, so the
# client's first view doesn't wait on it.
module DocumentAttachments
  extend ActiveSupport::Concern

  MAX_ATTACHMENTS = 10
  ATTACHMENT_MAX_BYTES = 10.megabytes
  ATTACHMENT_TYPES = %w[image/png image/jpeg image/webp application/pdf].freeze

  included do
    has_many_attached :attachments do |attachable|
      attachable.variant :web, resize_to_limit: [ 640, 640 ], preprocessed: true
    end

    validate :attachments_are_allowed
  end

  # The files actually saved, from the database: after a refused save, the attachments that
  # failed (an upload, or a ticked photo whose blob already exists) aren't listed as if they had.
  def saved_attachments = attachments_attachments.includes(:blob).order(:id).to_a

  def attach_files(files)
    @attachment_errors = []
    Array(files).compact_blank.each do |file|
      name = file.respond_to?(:original_filename) ? file.original_filename : "file"
      if pdf?(file)
        next @attachment_errors << "#{name} must be smaller than #{ATTACHMENT_MAX_BYTES / 1.megabyte} MB" if file.size > ATTACHMENT_MAX_BYTES

        attachments.attach(file)
      else
        result = LogoUpload.clean_photo(file, max_bytes: ATTACHMENT_MAX_BYTES)
        next @attachment_errors << "#{name} #{result.error.sub(LogoUpload::TYPE_ERROR, "must be a photo (PNG, JPEG, WebP) or a PDF")}" if result.error

        attachments.attach(result.attachable)
      end
    end
  end

  # A real PDF starts with "%PDF-"; the name or claimed type doesn't count. (PDFs are kept as
  # uploaded, metadata included; only photos are re-encoded.)
  def pdf?(file)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    header = io.read(5).tap { io.rewind }
    header == "%PDF-"
  end

  private

  def attachments_are_allowed
    Array(@attachment_errors).each { errors.add(:base, _1) }
    errors.add(:base, "This #{model_name.human.downcase} can have at most #{MAX_ATTACHMENTS} files.") if attachments.size > MAX_ATTACHMENTS
  end
end
