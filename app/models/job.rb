# Work the business has committed to do (JOB-01): for one client, usually at one of their
# properties. A job is made from an approved quote (its client, property, line items, internal
# notes and files are copied, and the two are linked) or from scratch for work agreed by phone.
#
# Status: Unscheduled, Scheduled and In progress follow the job's visits (JOB-02); Completed
# and Cancelled are set by staff, and a job can be reopened. Totals come from
# Pricing::DocumentTotals; the *_cents columns are a cache for lists, refreshed on every save.
class Job < ApplicationRecord
  include BusinessOwned
  include AtLocation # CAT-07
  include PricedDocument

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
  has_many :email_messages, as: :related, dependent: :nullify # JOB-05: what the client was sent
  has_many :visits, inverse_of: :job, dependent: :restrict_with_exception # JOB-02
  after_update :keep_visit_clock_times, if: :saved_change_to_location_id? # CAT-07
  has_many :invoices, dependent: :restrict_with_exception # PAY-01: one or more (progress billing)
  has_many :claims, class_name: "JobClaim", inverse_of: :job, dependent: :restrict_with_exception # JOB-09: its share of the quote
  has_many :work_entries, -> { order(:created_at, :id) }, inverse_of: :job, dependent: :restrict_with_exception # JOB-09
  accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :blank_new_line?

  MAX_LINES = 100
  has_many_attached :attachments do |attachable|
    attachable.variant :web, resize_to_limit: [ 640, 640 ], preprocessed: true
  end


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
  before_save :lock_quote_work, if: -> { quote_id && persisted? }
  after_save { @quote_lines = nil }
  # Prices typed into a new job's lines need its currency before it's saved.
  after_initialize { self.currency ||= (business || Current.business)&.currency_code if new_record? }

  scope :unfinished, -> { where(status: OPEN_STATUSES) }

  # The list's tabs. "Needs scheduling" is the approved-but-unscheduled shortcut.
  FILTERS = { "open" => "Not finished", "unscheduled" => "Needs scheduling", "scheduled" => "Scheduled", "in_progress" => "In progress",
              "completed" => "Completed", "to_invoice" => "Ready to invoice", "cancelled" => "Cancelled", "all" => "All" }.freeze

  # INS-01: finished, and not billed yet: no invoice that went out (a draft or a void one
  # doesn't count) for the job, or for the quote it came from (a deposit invoice).
  def self.ready_to_invoice
    sent = Invoice.where.not(status: "void").where.not(sent_at: nil)
    where(status: "completed").where.not(id: sent.where.not(job_id: nil).select(:job_id))
                              .where("jobs.quote_id IS NULL OR jobs.quote_id NOT IN (?)", sent.where.not(quote_id: nil).select(:quote_id))
  end

  def self.filtered(filter)
    case filter
    when "all" then all
    when "open" then unfinished
    when "to_invoice" then ready_to_invoice
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
             when "to_invoice" then ready_to_invoice.count
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

  # JOB-09: a job for an approved quote's work. `picks` ({ quote line id => quantity }) is what
  # the picker ticked; without it the job takes everything still to do (the automatic job on
  # approval and NTF-04). It's refused when nothing is left, or when a line hasn't that much to
  # do, naming the jobs that hold it. `token` is the picker's: sending the same picker again opens
  # the job it made, or the picker again if that job was cancelled.
  #
  # With the flag off a quote has one job, as before JOB-09: a second call (a double click, the
  # automatic one racing the button) returns it, and its lines copy the quote's in full, each
  # claiming what's still free (work billed straight from the quote isn't claimed twice).
  def self.from_quote!(quote, by: nil, picks: nil, token: nil)
    split = QuoteWork.split?(quote.business)
    return quote.first_job if !split && quote.first_job

    transaction(requires_new: true) do # a savepoint: a failure here can't spoil a surrounding approval
      lines = QuoteWork.lock!(quote.id)
      quote.reload
      raise NotOpen, "Only an approved quote becomes a job." unless quote.status == "approved"
      next quote.first_job if !split && quote.first_job
      if token.present? && (made = quote.jobs.find_by(picker_token: token))
        raise NotOpen, "#{made.number}, made from this picker, was cancelled. Choose the work again." if made.status == "cancelled"

        next made
      end

      taken = pick_list(quote, lines, picks, split:)
      job = build_for_quote(quote, taken, by:, split:, token: (token.presence if split))
      job.save!
      taken.each { |line, quantity, job_line| QuoteWork.claim!(job, line, split ? quantity : [ quantity, line.to_do_quantity ].min, job_line:) }
      quote.attachments.each { job.attachments.attach(_1.blob) }
      %i[first_job jobs].each { quote.association(_1).reset } # the caller's quote now has it
      job
    end
  rescue ActiveRecord::RecordNotUnique
    quote.reload
    (token.present? && quote.jobs.find_by(picker_token: token)) || (!split && quote.first_job) || raise
  end

  # [quote line, quantity] for each line a new job (or more of an open one) takes, in quote order.
  # With the flag off, every line in full, as before.
  def self.pick_list(quote, lines, picks, split: true)
    ordered = lines.values.sort_by { [ _1.position, _1.id ] }
    return ordered.map { [ _1, _1.quantity.to_d ] } unless split

    taken = if picks.nil?
      ordered.select { _1.to_do_quantity.positive? || _1.quantity.to_d.zero? }.map { [ _1, _1.to_do_quantity ] }
    else
      wanted = picks.to_h.transform_keys(&:to_i)
      ordered.filter_map { |line| (quantity = wanted[line.id]) && [ line, quantity.to_d ] }.select { _2.positive? }
    end
    if taken.empty? && !(picks.nil? && lines.empty?) # a quote without lines still makes a job, as before
      holders = quote.jobs.where.not(status: "cancelled").pluck(:number)
      raise NotOpen, picks.nil? && holders.any? ? "Everything on quote #{quote.number} is already in #{holders.to_sentence}." : "Choose at least one line to do."
    end
    taken.each { |line, quantity| raise QuoteWork::Refused, QuoteWork.refusal(line, quantity) if quantity > line.to_do_quantity }
    taken
  end

  # The job, its lines copied with what it takes. Split jobs carry no fixed discount, the quote's
  # or a line's (PAY-08 shares them on invoices); a percent discount is copied as before.
  def self.build_for_quote(quote, taken, by:, split:, token:)
    discount = split && quote.discount_kind == "amount" ? {} : { discount_kind: quote.discount_kind, discount_percent: quote.discount_percent, discount_amount_cents: quote.discount_amount_cents }
    job = new(client: quote.client, property: quote.property || quote.client.primary_property, quote:, created_by: by, currency: quote.currency,
              title: title_for(quote, taken, split:), picker_token: token, internal_notes: quote.internal_notes,
              tax_rates: quote.tax_rates, prices_include_tax: quote.prices_include_tax, **discount)
    taken.each_with_index do |(line, quantity), index|
      job_line = job.line_items.build(line.attributes.slice(*JobLineItem::COPIED).merge("quantity" => quantity, "position" => index))
      job_line.name = "Item" if job_line.name.blank?
      job_line.set_discount(nil, nil) if split && job_line.discount_kind == "amount"
      taken[index] << job_line
    end
    job
  end

  # The quote's title when the job takes everything, else its lines: "Tree removal (6 of 10)".
  def self.title_for(quote, taken, split:)
    whole = !split || (taken.size == quote.line_items.size && taken.all? { |line, quantity| quantity == line.quantity.to_d })
    title = (quote.title.presence if whole) ||
            (split && taken.map { |line, quantity| quantity == line.quantity.to_d ? line.name : "#{line.name} (#{QuoteWork.number(quantity)} of #{QuoteWork.number(line.quantity)})" }.join(", ").presence) ||
            quote.line_items.first&.name.presence || "Work for #{quote.client.display_name}"
    title.truncate(120, separator: " ")
  end

  # JOB-09: more to-do work from its quote on this open job: a line it already has grows, others
  # are added. Refused as from_quote! is.
  def add_from_quote!(picks)
    raise NotOpen, "#{number} isn't from a quote." unless quote

    transaction do
      lines = QuoteWork.lock!(quote_id, jobs: [ self ])
      reload
      raise NotOpen, "#{number} is #{status_label.downcase}. Reopen it to add work." unless open?

      position = line_items.maximum(:position).to_i
      Job.pick_list(quote, lines, picks).each do |line, quantity|
        claim = claims.find_by(quote_line_item: line)
        job_line = claim&.job_line_item
        if job_line
          job_line.update_columns(quantity: job_line.quantity.to_d + quantity, updated_at: Time.current)
        else # a new line; an old claim without a line (from before JOB-09) gets one for all it holds
          held = claim ? claim.quantity.to_d : 0
          job_line = line_items.create!(line.attributes.slice(*JobLineItem::COPIED).merge("quantity" => held + quantity, "position" => position += 1, "name" => line.name.presence || "Item"))
          job_line.set_discount(nil, nil) if job_line.discount_kind == "amount"
          job_line.save! if job_line.changed?
        end
        QuoteWork.claim!(self, line, quantity, job_line:)
      end
      line_items.reset
      save!
    end
  end

  def status_label = LABELS.fetch(status)
  def open? = OPEN_STATUSES.include?(status)

  # Status changes take the row lock and look again, so two people pressing at once (or a visit
  # changing it, JOB-02) can't both win.
  # Finishing a job finishes its visits too (JOB-02): a visit under way is done, and ones not
  # started are cancelled. Cancelling a job cancels all its open visits.
  # Completing a job doesn't email the client about visits it cancels (the work is done); they
  # simply count as what the client knows.
  #
  # JOB-09: with the split_jobs flag, completing confirms what was done (`done`: { job line id =>
  # quantity }, else each line's logged total, else what it booked); it's final. Lines added on
  # site without a price get one first (`prices`: { job line id => amount }; $0 typed on purpose).
  def complete!(by:, notify_client: false, done: nil, prices: nil)
    under_quote_lock do
      raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

      if QuoteWork.split?(business)
        price_site_lines!(prices.to_h.transform_keys(&:to_i))
        QuoteWork.confirm!(self, done_so_far.merge(done.to_h.transform_keys(&:to_i)), quote_lines)
        line_items.reset
      end
      update!(status: "completed", completed_at: Time.current, completed_by: by)
      ActiveRecord.after_all_transactions_commit { Automation.trigger("job_completed", self) } unless Current.automation_run # NTF-04
      ended = visits.open.lock.to_a.each { _1.finish!(_1.status == "in_progress" ? "completed" : "cancelled", by:, reason: "Job completed", notify: false) }
      tell_crew_job_ended(ended, "completed", by:)
      ended.find { _1.status == "cancelled" }&.tell_client(notify_client, ended, by:)
    end
  end

  # JOB-09: its quote lines are to do again (the claims are kept for a reopen).
  def cancel!(by:, reason: nil, notify_client: true)
    under_quote_lock do
      raise NotOpen, "#{number} is already #{status_label.downcase}." unless open?

      lines = quote_lines # the quote's lines before the visits (the lock order)
      update!(status: "cancelled", cancelled_at: Time.current, cancelled_by: by, cancel_reason: reason)
      QuoteWork.release!(self, lines) if quote_id
      ended = visits.open.lock.to_a.each { _1.finish!("cancelled", by:, reason: "Job cancelled", notify: false) }
      tell_crew_job_ended(ended, "cancelled", by:)
      ended.first&.tell_client(notify_client, ended, by:)
    end
  end

  # JOB-05: changes to a job's visits reach the client as one email, a few minutes after the
  # last of them, so a burst of edits (or a booking moved straight away) doesn't become several.
  CLIENT_NOTICE_DELAY = 3.minutes

  # #289: the visit email this job's waiting changes would send now, if any: the client has an
  # address and at least one change is of a kind the business sends. What the job page promises.
  def client_notice_pending?
    return false if client_notice_due_at.nil? || client.primary_email.nil?

    visits.where(status: %w[scheduled cancelled]).any? { (kind = _1.client_change_kind) && business.client_visit_email?(kind) }
  end

  def queue_client_notice!
    due = CLIENT_NOTICE_DELAY.from_now
    update_columns(client_notice_due_at: due)
    ids = [ business_id, id ]
    ActiveRecord.after_all_transactions_commit { VisitClientNoticeJob.set(wait_until: due).perform_later(*ids) }
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

  # Back to the status its visits give it, undoing Complete or Cancel. JOB-09: a cancelled job
  # takes back what it held, refused while that's in another job. With the split_jobs flag a
  # completed job reopens only while no invoice that isn't void bills it, and its lines go back
  # to what they booked.
  def reopen!
    under_quote_lock do
      raise NotOpen, "#{number} is already open." if open?

      QuoteWork.reclaim!(self, quote_lines) if status == "cancelled" && quote_id
      if status == "completed" && QuoteWork.split?(business)
        billing = invoices.where.not(status: "void").order(:id).pluck(:number)
        raise NotOpen, "#{number} can't be reopened while #{billing.to_sentence} bills it. Void #{billing.one? ? "it" : "them"} first." if billing.any?

        QuoteWork.restore_booked!(self, quote_lines)
        line_items.reset
      end
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

  # JOB-09: someone's work from a visit (My day), or the office correcting it: `totals` is what
  # `user` did on each line on that visit ({ job line id => quantity }). Each change is a new
  # entry for the difference, so the log keeps its history and two people logging at once never
  # overwrite each other. Takes the job's lock and needs the job open: done means done.
  def log_work!(user:, by:, totals:, visit: nil)
    with_lock do
      raise NotOpen, "#{number} is #{status_label.downcase}, so its work can't change." unless open?

      lines = line_items.index_by(&:id)
      # Typed entries only: JOB-11's tracked time is its own (source "time").
      had = WorkEntry.where(job_id: id, user_id: user.id, visit_id: visit&.id, source: "logged").group(:job_line_item_id).sum(:quantity)
      totals.to_h.transform_keys(&:to_i).filter_map do |line_id, total|
        next unless (line = lines[line_id])

        total = total.to_d
        raise QuoteWork::Refused, "#{line.name}: what was done can't be less than zero." if total.negative?

        change = total - had.fetch(line_id, 0).to_d
        WorkEntry.create!(job: self, job_line_item: line, visit:, user:, recorded_by: by, quantity: change) unless change.zero?
      end
    end
  end

  # JOB-09: something done on site that the job didn't have: a catalog service at its price at the
  # job's location, or a custom line with no price, which the office prices before invoicing. It's
  # the job's own (no quote line), logged as `user`'s work.
  def add_site_line!(user:, by:, quantity:, visit: nil, catalog_item: nil, name: nil)
    quantity = quantity.to_s.strip.presence&.to_d
    raise QuoteWork::Refused, "Say how many were done." unless quantity&.positive?
    raise QuoteWork::Refused, "Choose a service or type what was done." unless catalog_item || name.to_s.strip.present?

    with_lock do
      raise NotOpen, "#{number} is #{status_label.downcase}, so its work can't change." unless open?

      attributes = { position: line_items.maximum(:position).to_i + 1, quantity: }
      attributes.merge!(catalog_item ? catalog_item.line_attributes.except("catalog_item_uid").merge("catalog_item_id" => catalog_item.id, "unit_price_cents" => catalog_item.price_at(location)&.cents || 0)
                                     : { name: name.to_s.squish.first(200), unit_price_cents: 0, price_pending: true })
      line = line_items.create!(attributes)
      WorkEntry.create!(job: self, job_line_item: line, visit:, user:, recorded_by: by, quantity:)
      line_items.reset
      save!
      line
    end
  end

  # Each unpriced line added on site needs a price typed for it (owner, 2026-11-23).
  def price_site_lines!(prices)
    unpriced = line_items.select(&:price_pending)
    missing = unpriced.reject { prices[_1.id].to_s.strip.match?(/\A\d+(\.\d{1,2})?\z/) }
    raise QuoteWork::Refused, "Price #{missing.map(&:name).to_sentence} before completing (type 0 for no charge)." if missing.any?

    unpriced.each { _1.update!(unit_price: prices[_1.id].to_s.strip, price_pending: false) }
    line_items.reset
  end

  # Who did what on each line: { job line id => [[user, quantity], ...] }, people with nothing
  # left after corrections dropped ("Marcus 4, Riley 2").
  def work_by_person
    sums = WorkEntry.where(job_id: id).where.not(job_line_item_id: nil).group(:job_line_item_id, :user_id).sum(:quantity)
    users = User.where(id: sums.keys.map(&:last).uniq).index_by(&:id)
    sums.reject { _2.zero? }.each_with_object(Hash.new { |hash, key| hash[key] = [] }) { |((line_id, user_id), quantity), by_line| by_line[line_id] << [ users[user_id], quantity ] }
  end

  # JOB-09: what's been logged on each line, else what it booked: where completion starts.
  def done_so_far
    logged = WorkEntry.where(job_id: id).group(:job_line_item_id).sum(:quantity)
    line_items.to_h { [ _1.id, logged.fetch(_1.id, _1.quantity) ] }
  end

  # JOB-09: the quote's lines, locked in order (the quote and this job first), for claim changes.
  def quote_lines
    return {} unless quote_id

    @quote_lines ||= QuoteWork.lock!(quote_id, jobs: [ id ])
  end

  private

  # JOB-09's lock order: the quote, then this job (reloaded, as with_lock does), then its visits
  # and the quote's lines as the change needs them.
  def under_quote_lock(&)
    transaction do
      Quote.where(id: quote_id).lock.pluck(:id) if quote_id
      with_lock(&)
    end
  ensure
    @quote_lines = nil
  end

  # A job form changing lines from a quote takes the locks before the job's row is written.
  def lock_quote_work
    quote_lines if association(:line_items).loaded? && line_items.any?(&:changed_for_autosave?)
  end

  # CAT-07: a job moved to a location in another time zone keeps its visits' clock times (9 am
  # stays 9 am, on the new location's clock), rather than the same moments.
  def keep_visit_clock_times
    before, after = Location.find_by(id: location_id_before_last_save), location
    from, to = before&.time_zone, after.time_zone
    return if from.nil? || from.tzinfo.identifier == to.tzinfo.identifier

    move = ->(time) { time && to.local(*time.in_time_zone(from).then { [ _1.year, _1.month, _1.day, _1.hour, _1.min ] }) }
    visits.where.not(starts_at: nil).find_each do |visit|
      visit.update_columns(starts_at: move.(visit.starts_at), window_ends_at: move.(visit.window_ends_at))
    end
  end

  # An added row left empty is ignored rather than an error.
  def blank_new_line?(row)
    row["id"].blank? && %w[name description catalog_item_uid].all? { row[_1].blank? } && row["unit_price"].to_s.delete("^1-9").empty?
  end

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:job)
    self.currency ||= business.currency_code
    self.tax_rates = TaxRate.for_new_document(client:, location:).map { { "name" => _1.name.to_s, "percent" => _1.percent.to_d.to_s("F") } } if tax_rates.blank? && quote.nil?
  end

  def location_source = quote
end
