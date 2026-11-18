# One line of work on a job (JOB-01): copied from the approved quote, or added to the job.
# The job's copy can change on site; the quote keeps what the client agreed to, and the
# invoice will use these. Shared with quote lines through DocumentLine.
class JobLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  COPIED = %w[catalog_item_id position name description quantity unit unit_price_cents taxable
              discount_kind discount_percent discount_amount_cents].freeze

  belongs_to :job, inverse_of: :line_items
  belongs_to_business_record :catalog_item, optional: true

  # A nested new line gets its price before its job is attached.
  def document_currency = job&.currency || business&.currency_code || Current.business.currency_code

  before_validation { self.business ||= job&.business }

  validates :name, presence: { message: "is needed for each item" }

  # From the job form: the catalog item by uid (blank for a custom line).
  def catalog_item_uid = catalog_item&.uid

  def catalog_item_uid=(uid)
    self.catalog_item_id = catalog_item_id_for(uid.to_s)
  end
end
