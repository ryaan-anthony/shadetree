# OPS-02: what an operator sees about one business: members, plan and usage, activity counts,
# setup progress and history. Counts and dates only; never a client's name or details.
class Ops::BusinessSummary
  COUNTS = {
    "clients" => "Clients", "quotes_sent" => "Quotes sent", "jobs" => "Jobs", "invoices" => "Invoices", "payments" => "Payments"
  }.freeze

  attr_reader :business

  def initialize(business)
    @business = business
  end

  def entitlements = business.entitlements

  def members = business.business_users.includes(:user).order(Arel.sql("CASE role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END"), :created_at)

  def pending_invitations = as_business { Invitation.pending.count }

  def last_active_at = business.business_users.maximum(:last_active_at)

  def counts
    @counts ||= as_business do
      { "clients" => Client.count, "quotes_sent" => Quote.where.not(sent_at: nil).count, "jobs" => Job.count,
        "invoices" => Invoice.where.not(status: "draft").count, "payments" => Payment.count }
    end
  end

  # ACC-05's checklist, ticked from real data: [done, required].
  def setup_progress
    @setup_progress ||= as_business do
      checklist = SetupChecklist.new(business)
      [ checklist.done_count, checklist.required.size ]
    end
  end

  # Quotes sent per usage period (BIL-02), newest first.
  def usage_history(count: 6) = entitlements.period.history(count:).map { [ _1, _1.used ] }

  private

  def as_business(&) = Tenancy.with_business(business, &)
end
