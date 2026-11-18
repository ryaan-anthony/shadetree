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
  has_many :visits, inverse_of: :job, dependent: :restrict_with_exception # JOB-02
  accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :blank_new_line?

  MAX_LINES = 100
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
  validate(if: -> { @lines_assigned }) { errors.add(:base, "A job can have at most #{MAX_LINES} items.") if line_items.reject(&:marked_for_destruction?).size > MAX_LINES }
  # A change to the lines alone still changes the job's row, so its lock_version is checked
  # (and the lines saved) only if nobody else saved the job since the form was opened.
  before_save { self.updated_at = Time.current if !new_record? && line_items.any? { _1.changed_for_autosave? } && !changed? }
  validate { errors.add(:property, "must be one of this client's properties") if property && client && property.client_id != client.id }
  # Where the work happens: required once the client has a property (JOB-04 shows the crew the address).
  validate { errors.add(:property, "is needed: choose where the work happens") if property.nil? && client&.properties&.any? }
  validate { errors.add(:client, "is archived") if client&.archived? && (new_record? || will_save_change_to_client_id?) }

  before_validation :assign_number_and_defaults, on: :create
  # Prices typed into a new job's lines need its currency before it's saved.
  after_initialize { self.currency ||= (business || Current.business)&.currency_code if new_record? }
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

    title = quote.title.presence || quote.line_items.first&.name.presence || "Work for #{quote.client.display_name}"
    job = new(client: quote.client, property: quote.property || quote.client.primary_property, quote:, created_by: by, currency: quote.currency,
              title: title.truncate(120, separator: " "),
              internal_notes: quote.internal_notes, tax_rates: quote.tax_rates, prices_include_tax: quote.prices_include_tax,
              discount_kind: quote.discount_kind, discount_percent: quote.discount_percent, discount_amount_cents: quote.discount_amount_cents)
    quote.line_items.each { job.line_items.build(_1.attributes.slice(*JobLineItem::COPIED)).tap { |line| line.name = "Item" if line.name.blank? } }
    transaction(requires_new: true) do # a savepoint: a failure here can't spoil a surrounding approval
      job.save!
      quote.attachments.each { job.attachments.attach(_1.blob) }
    end
    job
  rescue ActiveRecord::RecordNotUnique
    quote.reload.job || raise
  end

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)

  # Status changes take the row lock and look again, so two people pressing at once (or a visit
  # changing it, JOB-02) can't both win.
  # Finishing a job finishes its visits too (JOB-02): a visit under way is done, and ones not
  # started are cancelled. Cancelling a job cancels all its open visits.
  def complete!(by:)
    with_lock do
      raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

      update!(status: "completed", completed_at: Time.current, completed_by: by)
      ended = visits.open.lock.to_a.each { _1.finish!(_1.status == "in_progress" ? "completed" : "cancelled", by:, reason: "Job completed", notify: false) }
      tell_crew_job_ended(ended, "completed", by:)
    end
  end

  def cancel!(by:, reason: nil)
    with_lock do
      raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

      update!(status: "cancelled", cancelled_at: Time.current, cancelled_by: by, cancel_reason: reason)
      ended = visits.open.lock.to_a.each { _1.finish!("cancelled", by:, reason: "Job cancelled", notify: false) }
      tell_crew_job_ended(ended, "cancelled", by:)
    end
  end

  # JOB-02: how long a visit should take, to start the form with: the catalog durations of its
  # items (times their quantities), else the business's industry default, else an hour.
  def suggested_visit_minutes
    from_items = visit_minutes_from_items
    minutes = from_items.positive? ? from_items : IndustryPreset.for(business.industry)&.default_visit_minutes || 60
    minutes.clamp(15, 8 * 60) # a starting point; a long job is usually more than one visit
  end

  def visit_minutes_from_items
    line_items.includes(:catalog_item).sum { (_1.catalog_item&.duration_minutes || 0) * _1.quantity.to_d }.round
  end

  # The people who were going on its upcoming visits hear once that they're off (not per visit).
  def tell_crew_job_ended(visits, how, by:)
    upcoming = visits.select { _1.status == "cancelled" && _1.scheduled_on >= business.today }
    crew = upcoming.flat_map { _1.assignees.to_a }.uniq
    return if crew.empty?

    upcoming.first.notify_crew("visit_cancelled", crew, "#{title} (#{number}) was #{how}: your #{upcoming.size == 1 ? "visit is" : "#{upcoming.size} visits are"} cancelled", by:)
  end

  # Visits it still has to happen: scheduled or under way.
  def open_visit_count = visits.open.count

  # JOB-02: the status its visits give an open job. Visits call it under the job's row lock, with
  # their change. Only the status is written: a visit change mustn't fail on (or re-save) the
  # job's other fields, or count as an edit to the job form open in another tab.
  def refresh_status!
    return unless open?

    new_status = visit_status
    update_columns(status: new_status, updated_at: Time.current) if new_status != status
  end

  # Back to the status its visits give it, undoing Complete or Cancel.
  def reopen!
    with_lock do
      raise NotOpen, "#{number} is already open." if open?

      update!(status: visit_status, completed_at: nil, completed_by: nil, cancelled_at: nil, cancelled_by: nil, cancel_reason: nil)
    end
  end

  # What the visits say: one under way, or work done with more to come, is In progress; visits
  # booked and none done yet is Scheduled; nothing booked is Unscheduled (needs scheduling).
  # Work done with nothing more booked stays In progress until staff complete the job.
  def visit_status
    statuses = visits.distinct.pluck(:status)
    if statuses.include?("in_progress") || statuses.include?("completed") then "in_progress"
    elsif statuses.include?("scheduled") then "scheduled"
    else "unscheduled"
    end
  end

  # The rows in the form, in the order they were sent.
  def line_items_attributes=(rows)
    @lines_assigned = true
    rows = rows.respond_to?(:values) ? rows.values : Array(rows)
    rows = rows.map(&:to_h)
    kept, removed = rows.partition { !ActiveModel::Type::Boolean.new.cast(_1["_destroy"]) }
    kept = kept.first(MAX_LINES + 1) # one over, so the limit is reported rather than silently applied
    super(kept.each_with_index.map { |row, index| row.merge("position" => index) } + removed)
  end

  def tax_rate_list = tax_rates.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  def totals
    Pricing::DocumentTotals.new(currency:, discount: pricing_discount, prices_include_tax:,
                                lines: line_items.reject(&:marked_for_destruction?).map { _1.to_pricing(tax_rate_list) })
  end

  def total = Money.new(total_cents, currency)

  private

  # An added row left empty is ignored rather than an error.
  def blank_new_line?(row)
    row["id"].blank? && %w[name description catalog_item_uid].all? { row[_1].blank? } && row["unit_price"].to_s.delete("^1-9").empty?
  end

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
