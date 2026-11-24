# A late bounce or complaint about one client email (NTF-05, ADR 0028), received at
# /inbound/email_events. .receive matches it in the request: to an email by our Message-ID or
# the reference header it carries (X-Shadetree-Email, the email's uid), and only if the
# recipient is the email's To or a CC of its send. Unmatched events, those more than 14 days
# after the email was sent, delays and temporary statuses are counted (EmailEventTally) and not
# stored. The rest are stored once (by event id, else a digest of the post) and processed in
# the background.
#
# Never the address, the server's diagnostic text or the payload: a row keeps the type, codes,
# reason, time, the email and the recipient's role (To or CC, and which CC).
class EmailEvent < ApplicationRecord
  include BusinessOwned

  TYPES = %w[bounce complaint].freeze
  ROLES = %w[to cc].freeze
  # mailbox: the address can't receive (send time's RecipientRefused statuses); refused: any
  # other permanent status, which doesn't blame the address.
  REASONS = %w[mailbox refused complaint].freeze
  LATE_AFTER = 14.days
  KEPT_FOR = 90.days

  belongs_to_business_record :email_message

  validates :event_key, presence: true
  validates :event_type, inclusion: { in: TYPES }
  validates :recipient_role, inclusion: { in: ROLES }
  validates :reason, inclusion: { in: REASONS }
  validates :occurred_at, presence: true

  scope :prunable, -> { where(created_at: ...KEPT_FOR.ago) }

  # Matches, stores and counts one parsed event (EmailEventIngress::Event). Returns :stored,
  # :repeat or the reason it was dropped (:temporary, :unmatched, :recipient, :late).
  def self.receive(event, now: Time.current)
    EmailEventTally.count!(:received)
    outcome = match_and_store(event, now)
    EmailEventTally.count!(outcome.in?(%i[stored repeat]) ? :matched : :dropped)
    outcome
  end

  def self.match_and_store(event, now)
    return :temporary if event.temporary? || !event.actionable?

    message = find_email(event) or return :unmatched
    Tenancy.with_business(message.business) do
      role, position = recipient_of(message, event)
      return :recipient unless role

      return :late if message.sent_at.nil?

      # Never before the send or in the future, whatever the report says.
      occurred_at = (event.occurred_at || now).clamp(message.sent_at, [ message.sent_at, now ].max)
      return :late if occurred_at > message.sent_at + LATE_AFTER

      key = event.key.first(255)
      # Event keys are unique across businesses: a key seen for another business is a repeat too.
      return :repeat if Tenancy.across_businesses(reason: "NTF-05: an event key is unique across businesses") { exists?(event_key: key) }

      row = create_with(email_message: message, event_type: event.type, status_code: event.status, reply_code: event.reply_code,
                        reason: reason_for(event), recipient_role: role, cc_position: position, occurred_at:)
              .create_or_find_by!(event_key: key)
      row.previously_new_record? ? :stored : :repeat
    rescue ActiveRecord::RecordNotFound # stored meanwhile for another business
      :repeat
    end
  end
  private_class_method :match_and_store

  # The lookup spans businesses: the event names our email, not a business (ADR 0028).
  def self.find_email(event)
    Tenancy.across_businesses(reason: "NTF-05: match a bounce report to the email it's about") do
      (EmailMessage.find_by(provider_message_id: event.message_id) if event.message_id) ||
        (EmailMessage.find_by(uid: event.reference) if event.reference)
    end
  end

  # ["to"] or ["cc", position], or nil when the recipient wasn't on the email. A complaint that
  # names no recipient is about the To.
  def self.recipient_of(message, event)
    return (event.type == "complaint" ? [ "to" ] : nil) if event.recipient.nil?
    return [ "to" ] if event.recipient == message.to

    position = message.cc_addresses.index(event.recipient)
    [ "cc", position ] if position
  end

  def self.reason_for(event)
    return "complaint" if event.type == "complaint"

    ClientMailDeliveryJob::RECIPIENT_STATUSES.include?(event.status) ? "mailbox" : "refused"
  end
end
