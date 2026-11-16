# What staff fill in to email a quote (QTE-04): recipient, optional CC, subject and message.
class QuoteSendForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_CC = 3
  EMAIL = URI::MailTo::EMAIL_REGEXP

  attribute :to, :string
  attribute :cc, :string
  attribute :subject, :string
  attribute :message, :string

  validates :to, presence: { message: "is needed: add the client's email address" }
  validates :subject, presence: true, length: { maximum: 200 }
  validates :message, length: { maximum: 5_000 }
  validate :addresses_are_valid
  validate :recipient_not_suppressed

  def to = super.to_s.strip.presence
  def cc_list = cc.to_s.split(/[,;\s]+/).map(&:strip).compact_blank.uniq
  def cc_header = cc_list.join(", ").presence

  private

  def addresses_are_valid
    errors.add(:to, "isn't a valid email address") if to && !to.match?(EMAIL)
    invalid = cc_list.reject { _1.match?(EMAIL) }
    errors.add(:cc, "has an address that isn't valid: #{invalid.first}") if invalid.any?
    errors.add(:cc, "can have up to #{MAX_CC} addresses") if cc_list.size > MAX_CC
  end

  def recipient_not_suppressed
    return unless to && EmailSuppression.suppressed?(to)

    errors.add(:to, "was refused by the mail server before. Check the address, or mark it as working on the client's page")
  end
end
