# An email address or phone number for a client (CLI-01). `normalized` is the form used to
# match duplicates and search: emails lowercased, phones reduced to digits.
class ClientContactMethod < ApplicationRecord
  include BusinessOwned

  KINDS = %w[email phone].freeze
  MIN_PHONE_DIGITS = 7
  MAX_PHONE_DIGITS = 15 # E.164

  belongs_to :client, inverse_of: :contact_methods

  normalizes :value, with: ->(value) { value.to_s.strip }
  normalizes :label, with: ->(value) { value.to_s.squish.presence }

  before_validation { self.business ||= client&.business }
  before_validation { self.normalized = self.class.normalize(kind, value) }

  validates :kind, inclusion: { in: KINDS }
  validates :value, presence: true, length: { maximum: 254 }
  validates :label, length: { maximum: 30 }
  validates :value, format: { with: URI::MailTo::EMAIL_REGEXP, message: "isn't an email address" }, if: :email?, allow_blank: true
  validate :phone_has_enough_digits, if: :phone?

  def self.normalize(kind, value)
    value = value.to_s.strip
    return if value.empty?

    case kind.to_s
    when "email" then value.downcase
    when "phone"
      digits = value.gsub(/\D/, "")
      # A leading 1 on an 11-digit number is the North American country code: drop it so
      # "+1 (555) 010-0100" and "555-010-0100" match.
      digits.length == 11 && digits.start_with?("1") ? digits[1..] : digits.presence
    end
  end

  def email? = kind == "email"
  def phone? = kind == "phone"

  # tel: and mailto: links. Phones keep a leading + so international numbers dial correctly.
  def href
    email? ? "mailto:#{value}" : "tel:#{value.start_with?("+") ? "+" : ""}#{value.gsub(/\D/, "")}"
  end

  private

  def phone_has_enough_digits
    digits = value.to_s.gsub(/\D/, "").length
    return if value.blank? || digits.between?(MIN_PHONE_DIGITS, MAX_PHONE_DIGITS)

    errors.add(:value, "needs #{MIN_PHONE_DIGITS} to #{MAX_PHONE_DIGITS} digits")
  end
end
