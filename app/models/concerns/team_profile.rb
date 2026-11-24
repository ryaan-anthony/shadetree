# ACC-09: a member's profile in one business: a photo, a title ("Lead technician"), a short bio
# and a work phone, all optional. The first name is the account's (ACC-06). Staff see the full
# name; clients only ever see what the client_* methods give, never a last name or email.
#
#   member.update(photo: params[:photo], title: "Lead technician")   # the photo is cleaned first
#   member.update(remove_photo: "1")
#   member.client_first_name                                         # "Marcus", or nil
#   member.client_phone(visit.contact)                               # work phone, else the location's
module TeamProfile
  extend ActiveSupport::Concern

  TITLE_MAX = 40
  BIO_MAX = 200
  PHONE_MAX = 40
  PHOTO_MAX_BYTES = 10.megabytes
  PHOTO_MAX_SIDE = 8_000
  PHOTO_MIN_SIDE = 128
  PHOTO_TYPES = LogoUpload::FORMATS.values.map(&:first).freeze
  # What a change is recorded as (ProfileEvent), in the order forms show them.
  FIELDS = { "photo" => "photo", "title" => "title", "bio" => "bio", "work_phone" => "work phone" }.freeze

  included do
    # Squares cut from the centre (no crop tool): small for lists, larger for profile pages and
    # client cards. Made in the background right after upload, so lists never resize originals.
    has_one_attached :photo do |attachable|
      attachable.variant :thumb, resize_to_fill: [ 96, 96 ], saver: { strip: true }, preprocessed: true
      attachable.variant :card, resize_to_fill: [ 256, 256 ], saver: { strip: true }, preprocessed: true
    end

    normalizes :title, :work_phone, with: ->(value) { value.to_s.squish.presence }
    # Plain text: kept as typed (line breaks too), shown escaped.
    normalizes :bio, with: ->(value) { value.to_s.gsub(/\r\n?/, "\n").strip.presence }

    validates :title, length: { maximum: TITLE_MAX }
    validates :bio, length: { maximum: BIO_MAX }
    validates :work_phone, length: { maximum: PHONE_MAX }
    validate :work_phone_dialable
    validate { errors.add(:photo, @photo_error) if @photo_error }

    attr_accessor :remove_photo
    before_save { photo.purge_later if removing_photo? && photo.attached? }
  end

  # Every photo goes through the shared cleaning (#358): decoded, turned upright, converted to
  # sRGB and stripped of its metadata (EXIF, GPS). A rejected file keeps the current photo and
  # adds an error on save; no file chosen changes nothing.
  def photo=(attachable)
    result = LogoUpload.clean_photo(attachable, max_bytes: PHOTO_MAX_BYTES, max_side: PHOTO_MAX_SIDE, min_side: PHOTO_MIN_SIDE)
    @photo_error = result.error&.sub("must be a PNG, JPEG or WebP image", "must be a PNG, JPEG or WebP photo")
    super(result.attachable) if result.attachable
  end

  # A reload forgets a rejected file, as it does other unsaved changes.
  def reload(...)
    @photo_error = nil
    super
  end

  # A stored photo, not one chosen in a form that hasn't saved (a page re-shown with errors can't
  # link to a file that isn't stored yet).
  def photo_saved? = photo.attached? && attachment_changes["photo"].nil? && photo.blob.persisted?

  def removing_photo? = ActiveModel::Type::Boolean.new.cast(remove_photo) && attachment_changes["photo"].nil?

  # The profile fields that differ from what's saved, by their FIELDS keys (before save).
  def profile_changes
    changed = FIELDS.keys.excluding("photo") & changes.keys
    changed.unshift("photo") if attachment_changes["photo"] || (removing_photo? && photo.attached?)
    changed
  end

  # Who may change `target`'s profile: themselves, people who manage the team, and for an Owner's
  # only people who manage Owners (ACC-07's rule). Never across businesses, or a deleted account.
  def can_edit_profile?(target)
    return false unless active? && target.business_id == business_id && !target.user.deleted?
    return true if target == self

    can?(:manage_team) && (!target.owner? || can?(:manage_owners))
  end

  # Changes someone else made, newest first (the rows go with the membership, by foreign key).
  def profile_history(limit: 20)
    Tenancy.with_business(business) { ProfileEvent.where(business_user_id: id).includes(:user).order(occurred_at: :desc, id: :desc).limit(limit).to_a }
  end

  # The only name a client may see: the account's first name, or nil (never the full name or
  # email that staff pages fall back to).
  def client_first_name = (user.first_name.to_s.squish.presence unless user.deleted?)
  def client_initial = client_first_name&.first&.upcase

  # The number clients see: the member's work phone, else the business's (`contact` is the
  # job's location, CAT-07); nil when neither is set. A personal number is never used.
  def client_phone(contact) = work_phone.presence || contact&.contact_phone.presence

  # ACC-06: deleting an account removes the photo (file and sizes) and the other fields in every
  # business. update_all skips callbacks, so this is explicit; the files go once it commits.
  def self.erase_for!(user)
    memberships = BusinessUser.where(user_id: user.id)
    attachments = ActiveStorage::Attachment.where(record_type: "BusinessUser", record_id: memberships.select(:id), name: "photo")
    blob_ids = attachments.pluck(:blob_id)
    attachments.delete_all
    memberships.update_all(title: nil, bio: nil, work_phone: nil, updated_at: Time.current)
    ActiveRecord.after_all_transactions_commit { PurgeDeletedFilesJob.perform_later(blob_ids) } if blob_ids.any?
  end

  private

  def work_phone_dialable
    return if work_phone.blank?

    digits = work_phone.gsub(/\D/, "").length
    min, max = ClientContactMethod::MIN_PHONE_DIGITS, ClientContactMethod::MAX_PHONE_DIGITS
    errors.add(:work_phone, "needs #{min} to #{max} digits") unless digits.between?(min, max)
  end
end
