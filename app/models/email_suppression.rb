# An address a business must not email again (NTF-01): it hard-bounced or the recipient
# marked a message as spam. Clearing it (after the address is fixed) allows sending again.
class EmailSuppression < ApplicationRecord
  include BusinessOwned

  REASONS = %w[hard_bounce complaint].freeze

  belongs_to :email_message, optional: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, uniqueness: { scope: :business_id }
  validates :reason, inclusion: { in: REASONS }

  def self.suppressed?(email) = exists?(email: email.to_s.strip.downcase)

  # Records the suppression and flags matching client email addresses.
  def self.suppress!(email, reason:, email_message: nil)
    record = find_or_initialize_by(email: email.to_s.strip.downcase)
    record.update!(reason:, email_message: record.email_message || email_message)
    ClientContactMethod.where(kind: "email", normalized: record.email).update_all(undeliverable_at: Time.current, undeliverable_reason: reason)
    record
  end

  # Staff confirmed a refused address is right: allow sending again. A spam complaint isn't
  # cleared: the address has to change.
  def self.clear!(email)
    email = email.to_s.strip.downcase
    return false if where(email:, reason: "complaint").exists?

    where(email:).delete_all
    ClientContactMethod.where(kind: "email", normalized: email).update_all(undeliverable_at: nil, undeliverable_reason: nil)
    true
  end

  def self.for(email) = find_by(email: email.to_s.strip.downcase)

  def reason_label = reason == "complaint" ? "marked an email as spam" : "bounced"
end
