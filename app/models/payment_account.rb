# A business's own Stripe account (PAY-03, Connect Standard): the business is the merchant of
# record, is paid out directly and handles refunds and disputes in its own Stripe dashboard.
# Shadetree keeps the account id and a copy of its status, which Stripe's account.updated
# notifications (ConnectEvent) and a fetch on return from onboarding keep in sync.
#
# One connected account per business (CAT-07: for all its locations). Disconnecting keeps the
# row, marked, and ends Shadetree's access; the business keeps its Stripe account.
class PaymentAccount < ApplicationRecord
  include BusinessOwned

  DASHBOARD_URL = "https://dashboard.stripe.com/".freeze
  STATUSES = {
    "onboarding_incomplete" => "Setup not finished",
    "pending_verification" => "Pending verification",
    "active" => "Active",
    "restricted" => "Restricted"
  }.freeze
  DISCONNECTED_REASONS = %w[owner provider business_deleted].freeze

  belongs_to :connected_by, class_name: "User", optional: true
  belongs_to :disconnected_by, class_name: "User", optional: true

  validates :account_id, presence: true, format: { with: /\Aacct_[A-Za-z0-9]+\z/ }
  validates :disconnected_reason, inclusion: { in: DISCONNECTED_REASONS }, allow_nil: true

  scope :connected, -> { where(disconnected_at: nil) }

  def self.current = connected.order(:id).last

  # The account a Stripe notification is about, whichever business it belongs to. Only
  # connected ones: events about an account a business has disconnected are ignored.
  def self.for_account(account_id)
    return if account_id.blank?

    Tenancy.across_businesses(reason: "matching a Stripe event to its business (PAY-03)") { connected.find_by(account_id:) }
  end

  def connected? = disconnected_at.nil?

  # Clients can pay once Stripe lets the account take charges (PAY-04).
  def accepts_payments? = connected? && charges_enabled?

  def status
    if !details_submitted? then "onboarding_incomplete"
    elsif charges_enabled? && payouts_enabled? && requirements_due.empty? then "active"
    elsif !charges_enabled? && requirements_due.empty? && (pending_verification_reason? || requirements_pending.any?) then "pending_verification"
    else "restricted"
    end
  end

  def status_label = STATUSES.fetch(status)

  # Why Stripe has limited the account, in words, for a restricted one.
  def restriction_reason
    reason = case disabled_reason.to_s
    when /\Arejected/ then "Stripe closed this account. Contact Stripe support for details."
    when "listed", "under_review" then "Stripe is reviewing the account."
    when "requirements.past_due" then "Stripe needs more information before it can turn payments back on."
    when "platform_paused" then "Payments are paused."
    end
    reason ||= if requirements_due.any?
      deadline = requirements_deadline && " by #{requirements_deadline.in_time_zone(business.time_zone).to_date.to_fs(:long)}"
      "Stripe needs more information#{deadline} to keep payments and payouts on."
    elsif !payouts_enabled? then "Payouts are paused until Stripe has what it needs."
    end
    reason || "Stripe has limited the account."
  end

  # Whether onboarding (Stripe's hosted pages) is the way to fix the account.
  def fixable_in_onboarding? = connected? && !disabled_reason.to_s.start_with?("rejected") && status != "active"

  # Copies what Stripe says about the account (an Account object, or its event payload).
  # Changes of status are kept in the business's history.
  def sync!(account)
    requirements = account["requirements"] || {}
    before = status
    update!(country: account["country"] || country,
            details_submitted: account["details_submitted"] == true,
            charges_enabled: account["charges_enabled"] == true,
            payouts_enabled: account["payouts_enabled"] == true,
            disabled_reason: requirements["disabled_reason"].presence,
            requirements_due: (Array(requirements["past_due"]) | Array(requirements["currently_due"])).sort,
            requirements_pending: Array(requirements["pending_verification"]).sort,
            requirements_deadline: requirements["current_deadline"].presence && Time.zone.at(requirements["current_deadline"].to_i),
            synced_at: Time.current)
    Rails.logger.info("[payments] account #{uid} is now #{status}") if status != before
    self
  end

  # Ends Shadetree's access at Stripe (unless Stripe told us it already ended) and marks the
  # account disconnected. Pay buttons disappear with it; recorded payments stay.
  def disconnect!(reason:, by: nil, gateway: PaymentGateway.current)
    return self unless connected?

    gateway.disconnect(account_id) unless reason == "provider"
    update!(disconnected_at: Time.current, disconnected_reason: reason, disconnected_by: by, charges_enabled: false, payouts_enabled: false)
    self
  end

  private

  def pending_verification_reason? = disabled_reason.to_s.include?("pending_verification") || disabled_reason.to_s == "under_review"
end
