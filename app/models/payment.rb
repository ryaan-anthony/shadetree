# Money received against an invoice (PAY-05). Staff record cash, checks, bank transfers and
# the like; online card payments arrive from PAY-04 and can't be changed here. Recording,
# changing or deleting one recalculates the invoice (Invoice#apply_payments!).
class Payment < ApplicationRecord
  include BusinessOwned
  include HasMoney

  SOURCES = %w[recorded online].freeze
  METHODS = { "cash" => "Cash", "check" => "Check", "bank_transfer" => "Bank transfer", "other" => "Other", "card" => "Card" }.freeze
  RECORDED_METHODS = %w[cash check bank_transfer other].freeze

  belongs_to_business_record :invoice
  belongs_to :recorded_by, class_name: "User", optional: true

  def contact = invoice.contact # CAT-07: receipts come from the invoice's location
  has_many :email_messages, as: :related, dependent: :nullify # its receipt

  # The invoice's currency, set before the amount is read (it can be assigned first).
  money :amount, currency: -> { self.currency ||= invoice&.currency }

  normalizes :reference, with: ->(value) { value.to_s.squish.presence }
  normalizes :note, with: ->(value) { value.to_s.strip.presence }

  validates :source, inclusion: { in: SOURCES }
  validates :payment_method, inclusion: { in: METHODS.keys }
  validates :payment_method, inclusion: { in: RECORDED_METHODS, message: "isn't one staff can record" }, if: :recorded?
  validates :amount, presence: true
  validate { errors.add(:amount, "must be more than zero") if amount_cents && amount_cents <= 0 }
  validates :received_on, presence: true
  validates :reference, length: { maximum: 100 }
  validates :note, length: { maximum: 1_000 }
  validate :received_on_is_plausible

  scope :chronological, -> { order(:received_on, :created_at, :id) }

  before_validation { self.currency ||= invoice&.currency }

  delegate :client, to: :invoice

  def recorded? = source == "recorded"
  def online? = source == "online"
  def method_label = METHODS.fetch(payment_method)

  # What the history records about it.
  def summary = { "amount_cents" => amount_cents, "currency" => currency, "method" => payment_method, "received_on" => received_on&.iso8601, "reference" => reference }.compact

  private

  # Not in the future (in the business's time zone), and not decades back by a typo.
  def received_on_is_plausible
    return unless received_on

    errors.add(:received_on, "can't be in the future") if received_on > business.today
    errors.add(:received_on, "is too far back") if received_on < business.today - 10.years
  end
end
