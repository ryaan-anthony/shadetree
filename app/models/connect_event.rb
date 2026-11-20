# A Stripe notification about a connected account (PAY-03, PAY-04), received at
# /webhooks/stripe/connect. Stored once per event id, so a repeated delivery is a no-op, then
# processed in the background (ProcessConnectEventJob). Platform-level: it's matched to a
# business through the account it names, and events for accounts we don't know are ignored.
#
# Only the fields the app acts on are kept (FIELDS): never names, emails, addresses or card
# details, and the raw payload is neither stored nor logged (PLT-10).
class ConnectEvent < ApplicationRecord
  STATUSES = %w[received processed ignored failed].freeze
  KEPT_FOR = 90.days

  # What's kept of each kind of object, by event type prefix.
  FIELDS = {
    "account" => [ "id", "country", "details_submitted", "charges_enabled", "payouts_enabled",
                   { "requirements" => %w[currently_due past_due pending_verification disabled_reason current_deadline] } ],
    "checkout.session" => [ "id", "status", "payment_status", "amount_total", "currency", "payment_intent", "client_reference_id",
                            { "metadata" => %w[shadetree_invoice shadetree_business] } ],
    "payment_intent" => [ "id", "status", "amount_received", "currency", "latest_charge", { "metadata" => %w[shadetree_invoice shadetree_business] } ],
    "charge.dispute" => %w[id charge payment_intent amount currency status reason],
    "charge" => %w[id payment_intent amount amount_refunded refunded currency]
  }.freeze

  validates :event_id, :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :prunable, -> { where(created_at: ...KEPT_FOR.ago) }

  # Stores a verified event (a parsed Stripe Event hash). Returns the row to process: a new one,
  # or one whose processing failed before (Stripe delivers it again); nil when it's been handled.
  def self.receive!(event)
    object = event.dig("data", "object") || {}
    row = create_with(event_type: event["type"].to_s, account_id: event["account"].presence, livemode: event["livemode"] == true,
                      data: slice(event["type"].to_s, object)).create_or_find_by!(event_id: event.fetch("id"))
    row.previously_new_record? || row.status == "failed" ? row : nil
  end

  def self.slice(type, object)
    prefix = FIELDS.keys.select { type.start_with?("#{_1}.") }.max_by(&:length)
    prefix ? pick(object, FIELDS.fetch(prefix)) : {}
  end

  def self.pick(object, fields)
    fields.each_with_object({}) do |field, kept|
      if field.is_a?(Hash)
        field.each { |key, inner| kept[key] = pick(object[key], inner) if object[key].is_a?(Hash) }
      elsif object.key?(field)
        kept[field] = object[field]
      end
    end
  end
  private_class_method :pick

  def object = data

  def finish!(status, error: nil) = update!(status:, error: error&.truncate(250), processed_at: Time.current)
end
