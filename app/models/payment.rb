# Money received against an invoice (PAY-05). Staff record cash, checks, bank transfers and
# the like; online card payments arrive from PAY-04 (Invoice#record_online_payment!) and can't be
# changed here. Recording, changing or deleting one recalculates the invoice
# (Invoice#apply_payments!). An online payment also carries what Stripe tells us later: refunds
# and a dispute (lost, its amount no longer counts as paid).
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
  validates :payment_method, presence: true
  validates :payment_method, inclusion: { in: METHODS.keys, message: "Choose a method from the list." }, allow_blank: true
  validates :payment_method, inclusion: { in: RECORDED_METHODS, message: "That method isn't one staff can record." }, if: -> { recorded? && payment_method.present? }
  validates :amount, presence: true
  validate { errors.add(:amount, "must be more than zero") if amount_cents && amount_cents <= 0 }
  validates :received_on, presence: true
  validates :reference, length: { maximum: 100 }
  validates :note, length: { maximum: 1_000 }
  validate :received_on_is_plausible

  scope :chronological, -> { order(:received_on, :created_at, :id) }

  # A card issuer's dispute (open, won, lost), or an inquiry that closed without one, or one
  # prevented before it became a dispute.
  DISPUTE_STATUSES = { "open" => "Disputed", "won" => "Dispute won", "lost" => "Dispute lost", "closed" => "Inquiry closed",
                       "prevented" => "Dispute prevented" }.freeze

  # What payments count towards what's been paid: their amounts, less refunds and lost disputes.
  COUNTED_SQL = "GREATEST(payments.amount_cents - payments.refunded_cents - CASE WHEN payments.dispute_status = 'lost' THEN payments.disputed_cents ELSE 0 END, 0)".freeze
  def self.counted_sum = sum(Arel.sql(COUNTED_SQL))
  validates :dispute_status, inclusion: { in: DISPUTE_STATUSES.keys }, allow_nil: true

  before_validation { self.currency ||= invoice&.currency }

  delegate :client, to: :invoice

  def recorded? = source == "recorded"
  def online? = source == "online"
  def method_label = METHODS.fetch(payment_method)

  # What it counts towards the invoice: the amount, less refunds and a lost dispute.
  def counted_cents = [ amount_cents - refunded_cents - (dispute_status == "lost" ? disputed_cents : 0), 0 ].max
  def refunded = Money.new(refunded_cents, currency)

  def counted = Money.new(counted_cents, currency)

  # What it counted before the changes not yet saved (a refund or dispute being applied).
  def counted_cents_was = [ amount_cents_was - refunded_cents_was - (dispute_status_was == "lost" ? disputed_cents_was : 0), 0 ].max

  # "Refunded", "Partly refunded", "Disputed", …, or nil. A dispute that's still open or was
  # lost says so first; otherwise a refund does.
  def adjustment_label
    return DISPUTE_STATUSES.fetch(dispute_status) if dispute_status.in?(%w[open lost])
    return "Refunded" if refunded_cents.positive? && refunded_cents >= amount_cents
    return "Partly refunded" if refunded_cents.positive?

    DISPUTE_STATUSES[dispute_status]
  end

  # What the history records about it.
  def summary = { "amount_cents" => amount_cents, "currency" => currency, "method" => payment_method, "received_on" => received_on&.iso8601, "reference" => reference,
                  "detail" => method_detail }.compact

  private

  # Not in the future (in the business's time zone), and not decades back by a typo.
  def received_on_is_plausible
    return unless received_on

    errors.add(:received_on, "can't be in the future") if received_on > business.today
    errors.add(:received_on, "is too far back") if received_on < business.today - 10.years
  end
end
