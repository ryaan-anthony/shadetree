# One line on a quote (QTE-01): a copy of a catalog item or a custom line. Amounts are cents
# in the quote's currency; Pricing::Line does the arithmetic. Shared with job lines through
# DocumentLine.
class QuoteLineItem < ApplicationRecord
  include BusinessOwned
  include DocumentLine

  belongs_to :quote, inverse_of: :line_items
  belongs_to :catalog_item, optional: true # set only through catalog_item_id_for, within the business

  # JOB-09: the jobs' shares of it. claimed_quantity is the sum of the live ones (QuoteWork).
  has_many :claims, class_name: "JobClaim", inverse_of: :quote_line_item, dependent: :restrict_with_exception
  attr_readonly :claimed_quantity # only QuoteWork's atomic updates change it

  def document_currency = quote.currency

  # What no job holds yet: "4 of 10 to do".
  def to_do_quantity = quantity.to_d - claimed_quantity.to_d

  before_validation { self.business ||= quote&.business }

  validates :key, presence: true, length: { maximum: 64 }

  # QTE-08: whether it needs the price its service had when added (new, or its service changed):
  # Quote#note_catalog_prices sets them together, a lookup per quote rather than per line.
  def catalog_price_due? = new_record? || will_save_change_to_catalog_item_id?
end
