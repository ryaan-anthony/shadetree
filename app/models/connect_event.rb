# A Stripe notification about a connected account (PAY-03, PAY-04), received at
# /webhooks/stripe/connect. Stored once per event id, so a repeated delivery is a no-op, then
# processed (process!, ConnectEventHandler) in the background: by ProcessConnectEventJob, and if
# that fails or never runs, by RetryConnectEventsJob, up to MAX_ATTEMPTS tries. Platform-level:
# it's matched to a business through the account it names; events for accounts we don't know,
# or from the other mode (test vs live), are ignored.
#
# Only the fields the app acts on are kept (FIELDS): never names, emails, addresses or card
# details, and the raw payload is neither stored nor logged (PLT-10).
class ConnectEvent < ApplicationRecord
  STATUSES = %w[received processed ignored failed].freeze
  KEPT_FOR = 90.days
  MAX_ATTEMPTS = 8
  RETRY_AFTER = 10.minutes

  # What's kept of each kind of object, by event type prefix.
  FIELDS = {
    "account" => [ "id", "country", "details_submitted", "charges_enabled", "payouts_enabled",
                   { "requirements" => %w[currently_due past_due pending_verification disabled_reason current_deadline] } ],
    "checkout.session" => [ "id", "status", "payment_status", "amount_total", "currency", "payment_intent", "client_reference_id",
                            { "metadata" => %w[shadetree_invoice shadetree_business shadetree_fee_cents] } ],
    "payment_intent" => [ "id", "status", "amount_received", "currency", "latest_charge", { "metadata" => %w[shadetree_invoice shadetree_business shadetree_fee_cents] } ],
    "charge.dispute" => %w[id charge payment_intent amount currency status reason],
    "charge" => %w[id payment_intent amount amount_refunded refunded currency]
  }.freeze

  validates :event_id, :event_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :prunable, -> { where(created_at: ...KEPT_FOR.ago) }
  # Not done, not given up on, and left alone for a while (a job may still be on it).
  scope :due_for_retry, -> { where(status: %w[received failed], attempts: ...MAX_ATTEMPTS, updated_at: ...RETRY_AFTER.ago) }

  # Stores a verified event (a parsed Stripe Event hash). Returns the row to process: a new one,
  # or one whose processing failed before (Stripe delivers it again); nil when it's been handled.
  def self.receive!(event)
    object = event.dig("data", "object") || {}
    created = event["created"].presence && Time.zone.at(event["created"].to_i)
    row = create_with(event_type: event["type"].to_s, account_id: event["account"].presence, livemode: event["livemode"] == true,
                      event_created_at: created, data: slice(event["type"].to_s, object)).create_or_find_by!(event_id: event.fetch("id"))
    row.previously_new_record? || (row.status == "failed" && row.attempts < MAX_ATTEMPTS) ? row : nil
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

  def done? = status.in?(%w[processed ignored])

  # Runs the handler once more, unless it's done or given up on. A failure is recorded and raised
  # (for the job's retries); on the last try it's reported once and not raised.
  def process!
    claimed = self.class.transaction do
      lock!
      next false if done? || attempts >= MAX_ATTEMPTS

      update!(attempts: attempts + 1)
    end
    return unless claimed

    begin
      finish!(ConnectEventHandler.handle(self))
    rescue StandardError => error
      finish!("failed", error: "#{error.class}: #{error.message}")
      raise if attempts < MAX_ATTEMPTS

      Rails.error.report(error, context: { connect_event: event_id, event_type:, gave_up_after: attempts })
    end
  end

  def finish!(status, error: nil) = update!(status:, error: error&.truncate(250), processed_at: Time.current)
end
