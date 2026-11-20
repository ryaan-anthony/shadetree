# OPS-05: one message in a support ticket: from the member, from an operator, or an operator's
# internal note (never shown to the business). Screenshots are re-encoded without metadata.
class SupportMessage < ApplicationRecord
  include BusinessOwned

  MAX_FILES = 5
  MAX_BYTES = 10.megabytes
  SOURCES = %w[app email system].freeze

  belongs_to :support_ticket, inverse_of: :messages
  belongs_to :author, class_name: "User", optional: true
  has_many_attached :files

  normalizes :body, with: ->(body) { body.to_s.strip }
  validates :body, presence: true, length: { maximum: 20_000 }
  validates :source, inclusion: { in: SOURCES }
  validate :files_are_allowed

  def attach_files(uploads)
    @file_errors = []
    Array(uploads).compact_blank.first(MAX_FILES + 1).each do |upload|
      result = LogoUpload.clean_photo(upload, max_bytes: MAX_BYTES)
      name = upload.respond_to?(:original_filename) ? upload.original_filename : "file"
      result.error ? @file_errors << "#{name} #{result.error}" : files.attach(result.attachable)
    end
  end

  # Who wrote it, as the business sees it: operators are "Shadetree support".
  def author_label = from_operator? ? "Shadetree support" : (author&.full_name.presence || "A former member")

  private

  def files_are_allowed
    Array(@file_errors).each { errors.add(:base, _1) }
    errors.add(:base, "Attach at most #{MAX_FILES} screenshots.") if files.size > MAX_FILES
  end
end
