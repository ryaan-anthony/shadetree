# One entry in a business's billing history (BIL-04/05): subscribing, switching, payments,
# failures, cancelling and the plan changes they caused. Shown to operators (OPS-02). Holds
# plan names, amounts and Stripe invoice numbers, never card or contact details.
class BillingEvent < ApplicationRecord
  include BusinessOwned

  KINDS = {
    "subscribed" => "Subscribed", "switched" => "Switched plan", "cancel_scheduled" => "Cancellation scheduled",
    "cancel_withdrawn" => "Cancellation withdrawn", "past_due" => "Renewal payment failing", "ended" => "Subscription ended",
    "payment_succeeded" => "Payment received", "payment_failed" => "Payment failed", "plan_changed" => "Plan changed"
  }.freeze

  validates :kind, inclusion: { in: KINDS.keys }

  scope :recent, -> { order(occurred_at: :desc, id: :desc) }

  # Adds an entry once: an entry with the same dedupe key (a Stripe invoice or attempt) is kept
  # as it is. Call with the business's tenancy set.
  def self.record!(kind, details: {}, dedupe_key: nil, at: Time.current)
    return if dedupe_key && exists?(dedupe_key:)

    create!(kind:, details: details.compact, dedupe_key:, occurred_at: at)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def label = KINDS.fetch(kind)

  # The entry in a few words, for the history list.
  def summary
    d = details
    case kind
    when "subscribed", "switched" then [ d["plan"], d["interval"] ].compact.join(", ")
    when "plan_changed" then "#{d["from"]} → #{d["to"]}"
    when "payment_succeeded", "payment_failed"
      [ d["amount_cents"] && Money.new(d["amount_cents"], d["currency"].to_s.upcase.presence || "USD").format, d["invoice"] && "invoice #{d["invoice"]}",
        d["attempt"] && d["attempt"] > 1 ? "attempt #{d["attempt"]}" : nil ].compact.join(" · ")
    when "cancel_scheduled" then d["ends_on"] && "ends #{d["ends_on"]}"
    else d["note"]
    end
  end
end
