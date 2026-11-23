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
  # JOB-09: the quote line it does (through its claim), and what was logged on it.
  has_one :claim, class_name: "JobClaim", inverse_of: :job_line_item, dependent: nil # the key nullifies
  has_one :quote_line_item, through: :claim
  has_many :work_entries, -> { order(:created_at, :id) }, inverse_of: :job_line_item, dependent: nil # the key nullifies: the log stays

  # JOB-09: on an open job its claim follows its quantity, and removing it frees what it held
  # (the job took the locks before saving: Job#quote_lines).
  after_update(if: -> { saved_change_to_quantity? && claim && job.open? }) { QuoteWork.follow!(self, job.quote_lines) }
  before_destroy(if: -> { claim && job.open? }) { QuoteWork.unclaim!(claim, job.quote_lines) }

  # JOB-09: a line added on site is priced when a price is typed for it (not by saving the form as is).
  before_update { self.price_pending = false if price_pending && will_save_change_to_unit_price_cents? }

  # Done so far: the sum of its log.
  def logged_quantity = WorkEntry.where(job_line_item_id: id).sum(:quantity)

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
