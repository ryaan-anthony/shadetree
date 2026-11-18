# Work the business has committed to do (JOB-01): for one client, usually at one of their
# properties. A job is made from an approved quote (its client, property, line items, internal
# notes and files are copied, and the two are linked) or from scratch for work agreed by phone.
#
# Status: Unscheduled, Scheduled and In progress follow the job's visits (JOB-02); Completed
# and Cancelled are set by staff, and a job can be reopened. Totals come from
# Pricing::DocumentTotals; the *_cents columns are a cache for lists, refreshed on every save.
class Job < ApplicationRecord
  include BusinessOwned
  include HasMoney
  include HasDiscount

  STATUSES = %w[unscheduled scheduled in_progress completed cancelled].freeze
  OPEN_STATUSES = %w[unscheduled scheduled in_progress].freeze
  LABELS = { "unscheduled" => "Unscheduled", "scheduled" => "Scheduled", "in_progress" => "In progress",
             "completed" => "Completed", "cancelled" => "Cancelled" }.freeze

  class NotOpen < StandardError; end

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  belongs_to_business_record :quote, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :completed_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  has_many :line_items, -> { order(:position, :id) }, class_name: "JobLineItem", inverse_of: :job, dependent: :delete_all
  has_many_attached :attachments do |attachable|
    attachable.variant :web, resize_to_limit: [ 640, 640 ], preprocessed: true
  end

  def discount_currency = currency

  normalizes :title, with: ->(value) { value.to_s.squish }
  normalizes :instructions, :internal_notes, with: ->(value) { value.to_s.strip.presence }
  normalizes :cancel_reason, with: ->(value) { value.to_s.squish.presence }

  validates :number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true, length: { maximum: 120 }
  validates :instructions, :internal_notes, length: { maximum: 5_000 }
  validates :cancel_reason, length: { maximum: 200 }
  validate { errors.add(:property, "must be one of this client's properties") if property && client && property.client_id != client.id }
  validate { errors.add(:client, "is archived") if client&.archived? && (new_record? || will_save_change_to_client_id?) }

  before_validation :assign_number_and_defaults, on: :create
  before_save :cache_totals

  scope :unfinished, -> { where(status: OPEN_STATUSES) }

  # The list's tabs. "Needs scheduling" is the approved-but-unscheduled shortcut.
  FILTERS = { "open" => "Open", "unscheduled" => "Needs scheduling", "scheduled" => "Scheduled", "in_progress" => "In progress",
              "completed" => "Completed", "cancelled" => "Cancelled", "all" => "All" }.freeze

  def self.filtered(filter)
    case filter
    when "all" then all
    when "open" then unfinished
    else where(status: filter)
    end
  end

  # How many jobs each tab holds, from one grouped count.
  def self.filter_counts
    by_status = unscope(:order).group(:status).count
    FILTERS.keys.to_h do |key|
      [ key, case key
             when "all" then by_status.values.sum
             when "open" then by_status.values_at(*OPEN_STATUSES).compact.sum
             else by_status.fetch(key, 0)
             end ]
    end
  end

  # By number, title, or the client's name, email or phone.
  def self.search(query)
    query = query.to_s.strip
    return all if query.empty?

    like = "%#{sanitize_sql_like(query)}%"
    where("jobs.number ILIKE :like OR jobs.title ILIKE :like", like:).or(where(client_id: Client.search(query).select(:id)))
  end

  # The job for an approved quote, made once: a second call (a double click, the automatic one
  # racing the button) returns the same job.
  def self.from_quote!(quote, by: nil)
    return quote.job if quote.job
    raise NotOpen, "Only an approved quote becomes a job." unless quote.status == "approved"

    job = new(client: quote.client, property: quote.property, quote:, created_by: by, currency: quote.currency,
              title: quote.title.presence || quote.line_items.first&.name.presence || "Work for #{quote.client.display_name}",
              internal_notes: quote.internal_notes, tax_rates: quote.tax_rates, prices_include_tax: quote.prices_include_tax,
              discount_kind: quote.discount_kind, discount_percent: quote.discount_percent, discount_amount_cents: quote.discount_amount_cents)
    quote.line_items.each { job.line_items.build(_1.attributes.slice(*JobLineItem::COPIED)) }
    transaction(requires_new: true) do # a savepoint: a failure here can't spoil a surrounding approval
      job.save!
      quote.attachments.each { job.attachments.attach(_1.blob) }
    end
    job
  rescue ActiveRecord::RecordNotUnique
    quote.reload.job
  end

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)

  def complete!(by:)
    raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

    update!(status: "completed", completed_at: Time.current, completed_by: by)
  end

  def cancel!(by:, reason: nil)
    raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

    update!(status: "cancelled", cancelled_at: Time.current, cancelled_by: by, cancel_reason: reason)
  end

  # Back to the status its visits give it, undoing Complete or Cancel.
  def reopen!
    raise NotOpen, "#{number} is already open." if open?

    update!(status: visit_status, completed_at: nil, completed_by: nil, cancelled_at: nil, cancelled_by: nil, cancel_reason: nil)
  end

  # What the visits say (JOB-02 fills this in): a job without visits is unscheduled.
  def visit_status = "unscheduled"

  def tax_rate_list = tax_rates.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  def totals
    Pricing::DocumentTotals.new(currency:, discount: pricing_discount, prices_include_tax:,
                                lines: line_items.reject(&:marked_for_destruction?).map { _1.to_pricing(tax_rate_list) })
  end

  def total = Money.new(total_cents, currency)

  private

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:job)
    self.currency ||= business.currency_code
    self.tax_rates = TaxRate.for_new_document(client:).map { { "name" => _1.name.to_s, "percent" => _1.percent.to_d.to_s("F") } } if tax_rates.blank? && quote.nil?
  end

  def cache_totals
    result = totals
    self.subtotal_cents = result.subtotal.cents
    self.discount_total_cents = (result.discount + Money.sum(result.lines.map(&:discount), currency)).cents
    self.tax_cents = result.tax_total.cents
    self.total_cents = result.total.cents
  end
end
