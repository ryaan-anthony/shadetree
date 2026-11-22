# Photos taken on site (JOB-04 visits, JOB-06 request follow-ups), cleaned like quote photos
# (re-encoded without their metadata: phone photos carry GPS) and capped per record.
module SitePhotos
  extend ActiveSupport::Concern

  private

  # Adds one photo to `attachment` (a has_many_attached). Returns an error sentence, or nil.
  # The count is checked again under the record's lock, so two phones uploading at once can't go
  # past `max`; the slow part (re-encoding) happens before taking it.
  def add_site_photo(attachment, file, by:, max:, max_bytes:, full:)
    return full if attachment.count >= max

    result = LogoUpload.clean_photo(file, max_bytes:)
    return "#{file.respond_to?(:original_filename) ? file.original_filename : "That file"} #{result.error.sub("must be a PNG, JPEG or WebP image", "isn't a photo we can use (PNG, JPEG or WebP)")}." if result.error

    with_lock do
      next full if attachment.count >= max

      attachment.attach(result.attachable.merge(metadata: { "uploaded_by" => by&.id }))
      nil
    end
  end
end
