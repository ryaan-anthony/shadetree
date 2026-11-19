# INS-01: what needs the office now, for the dashboard. Each group is a count and its top few
# records, each ready to link: new requests, quotes with changes asked for, quotes awaiting an
# answer (oldest first), jobs with nothing booked, today's visits by person, finished jobs not
# yet billed and overdue invoices (oldest first). Plus how the month is going.
class ActionDashboard
  TOP = 5

  Group = Data.define(:key, :title, :count, :items, :path) do
    def empty? = count.zero?
  end

  attr_reader :business, :today

  def initialize(business)
    @business = business
    @today = business.today
  end

  def groups
    @groups ||= [
      group(:new_requests, "New requests", ServiceRequest.where(status: "new").includes(:client).order(:created_at, :id), [ :admin_service_requests_path, {} ]),
      group(:changes_requested, "Changes asked for", quotes.where(status: "changes_requested").order(:updated_at, :id), [ :admin_quotes_path, { filter: "changes_requested" } ]),
      group(:awaiting_answer, "Quotes awaiting an answer", Quote.filtered("awaiting", today:).includes(:client).order(:sent_at, :id), [ :admin_quotes_path, { filter: "awaiting" } ]),
      group(:to_schedule, "Jobs to schedule", Job.where(status: "unscheduled").includes(:client).order(:created_at, :id), [ :admin_jobs_path, { filter: "unscheduled" } ]),
      group(:to_invoice, "Ready to invoice", Job.ready_to_invoice.includes(:client).order(:completed_at, :id), [ :admin_jobs_path, { filter: "to_invoice" } ]),
      group(:overdue, "Overdue invoices", Invoice.where(status: Invoice::OUTSTANDING).where(due_on: ...today).includes(:client).order(:due_on, :id), [ :admin_invoices_path, { filter: "overdue" } ])
    ]
  end

  # Today's open and done visits, by the people on them ("Not assigned" last).
  def todays_visits
    @todays_visits ||= begin
      visits = Visit.where(scheduled_on: today).where.not(status: "cancelled").includes(:business, :assignees, job: :client).in_order.to_a
      visits.flat_map { |visit| (visit.assignees.presence || [ nil ]).map { [ _1, visit ] } }
            .group_by(&:first).transform_values { _1.map(&:last) }
            .sort_by { |person, _| person ? [ 0, person.full_name ] : [ 1, "" ] }
    end
  end

  def visits_today_count = todays_visits.flat_map(&:last).uniq.size
  def empty? = groups.all?(&:empty?) && todays_visits.empty?

  # This month so far, in the business's time zone.
  def month = today.beginning_of_month..today

  # BIL-02: quotes sent in the usage period, and the plan's limit (nil when unlimited).
  def quotes_sent_this_month = entitlements.used(:quotes_sent)
  def quote_limit = entitlements.limit(:quotes_sent)
  def entitlements = @entitlements ||= business.entitlements

  # Of the quotes answered this month, the share approved, by each quote's latest answer (one
  # declined, revised and approved counts once, as approved). Nil when none were answered.
  def approval_rate
    latest = QuoteResponse.where(kind: %w[approved declined], created_at: month_range)
                          .select("DISTINCT ON (quote_responses.quote_id) quote_responses.kind")
                          .reorder(Arel.sql("quote_responses.quote_id, quote_responses.created_at DESC, quote_responses.id DESC"))
    kinds = latest.map(&:kind)
    kinds.empty? ? nil : (kinds.count("approved") * 100.0 / kinds.size).round
  end

  def payments_this_month = Payment.where(received_on: month).group(:currency).order(:currency).sum(:amount_cents).map { |currency, cents| Money.new(cents.to_i, currency) }

  private

  def quotes = Quote.unarchived.includes(:client)

  def group(key, title, scope, path) = Group.new(key:, title:, count: scope.unscope(:order, :includes).count, items: scope.limit(TOP).to_a, path:)

  def month_range = month.first.in_time_zone(business.time_zone).beginning_of_day..Time.current
end
