# A quote for a client (QTE-01). Drafts are built and autosaved in the builder; sending,
# the client page, approval and revisions come with QTE-02..QTE-06.
#
# Everything a client will see is copied onto the quote when it's made (line items from the
# catalog, tax rates, terms, currency), so later catalog, tax or settings changes never
# alter it. Totals always come from Pricing::DocumentTotals (PLT-08); the *_cents total
# columns are a cache for lists, refreshed on every save.
class Quote < ApplicationRecord
  include BusinessOwned
  include AtLocation # CAT-07
  include LocationRepricing # CAT-08
  include PricedDocument
  include BuiltDocument
  include DocumentAttachments
  include HasPdf
  include EmailedDocument # QTE-04, PAY-02: delivery warnings

  # QTE-04 sends (draft → sent); QTE-05 records the client's answer. "Viewed" comes from the
  # client link and "expired" from expires_on, so neither is stored.
  STATUSES = %w[draft sent approved declined changes_requested].freeze

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to_business_record :service_request, optional: true # CLI-04: the request it came from
  after_destroy { service_request&.quote_removed! }
  belongs_to :sent_by, class_name: "User", optional: true
  has_many :sends, -> { recent }, class_name: "QuoteSend", inverse_of: :quote, dependent: :delete_all
  has_many :email_messages, as: :related, dependent: :nullify
  has_many :responses, -> { order(:created_at, :id) }, class_name: "QuoteResponse", inverse_of: :quote, dependent: :delete_all
  has_one :approval, -> { where(kind: "approved") }, class_name: "QuoteResponse", inverse_of: :quote
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "QuoteEvent", inverse_of: :quote, dependent: :delete_all
  has_many :revisions, -> { order(:number) }, class_name: "QuoteRevision", inverse_of: :quote, dependent: :delete_all
  has_one :job, dependent: :nullify # JOB-01: the work it became
  has_many :invoices, dependent: :restrict_with_exception # PAY-01: what it was billed as
  has_many :line_items, -> { order(:position, :id) }, class_name: "QuoteLineItem", inverse_of: :quote,
           dependent: :delete_all, autosave: true

  normalizes :title, with: ->(value) { value.to_s.squish.presence }
  normalizes :message, :internal_notes, :terms, with: ->(value) { value.to_s.strip.presence }

  validates :number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :title, length: { maximum: 120 }
  validates :message, :terms, length: { maximum: 5_000 }
  validates :internal_notes, length: { maximum: 5_000 }
  validate :property_belongs_to_client

  before_validation :assign_number_and_defaults, on: :create

  scope :drafts, -> { where(status: "draft") }
  scope :unarchived, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # QTE-06: the list's tabs. "Expired" and "awaiting response" depend on the business's today.
  FILTERS = { "all" => "All", "awaiting" => "Awaiting response", "changes_requested" => "Changes requested", "draft" => "Drafts",
              "approved" => "Approved", "declined" => "Declined", "expired" => "Expired", "archived" => "Archived" }.freeze
  def self.filtered(filter, today:)
    case filter
    when "all" then unarchived
    when "archived" then archived
    when "awaiting" then unarchived.where(status: "sent").where("quotes.expires_on IS NULL OR quotes.expires_on >= ?", today)
    when "expired" then unarchived.where(status: "sent").where("quotes.expires_on < ?", today)
    else unarchived.where(status: filter)
    end
  end

  # How many quotes each tab holds, in one query.
  def self.filter_counts(today:)
    bucket = sanitize_sql_array([ <<~SQL.squish, today ])
      CASE WHEN quotes.archived_at IS NOT NULL THEN 'archived'
           WHEN quotes.status = 'sent' AND quotes.expires_on < ? THEN 'expired'
           WHEN quotes.status = 'sent' THEN 'awaiting'
           ELSE quotes.status END
    SQL
    counts = group(Arel.sql(bucket)).count
    FILTERS.keys.index_with { counts.fetch(_1, 0) }.merge("all" => counts.except("archived").values.sum)
  end

  # By quote number, or by client (name, phone, email or address, as CLI-02 searches).
  def self.search(query)
    query = query.to_s.strip
    return all if query.empty?

    where("quotes.number ILIKE ?", "%#{sanitize_sql_like(query)}%").or(where(client_id: Client.search(query).select(:id)))
  end

  def draft? = status == "draft"
  def sent? = status == "sent"
  # QA #274: an expired quote can't be answered as is; it's renewed with a revision (QTE-06),
  # whose own send is what counts, so an undelivered email isn't warned about meanwhile.
  def awaiting_client? = sent? && !expired?
  def approved? = status == "approved"
  # Only drafts change. A sent quote is revised (QTE-06); an approved one is locked for good.
  def editable? = draft?

  # QTE-06: a sent quote reopened as a draft of its next revision. The client sees that it's
  # being updated (not the unfinished edits) until it's sent again.
  def revising? = draft? && revision > 1

  # Any quote the client has been sent and hasn't approved: sent (expired or not), changes
  # requested, or declined. Not archived ones (restore first).
  def revisable? = status.in?(%w[sent changes_requested declined]) && !archived?

  # Keeps what the client was sent as revision N and reopens the quote as the draft of revision
  # N+1. The record is the snapshot (with its files, which are then kept even if removed from
  # the draft) plus the stored PDF if there is one: the same content as sent, though its status
  # line may say how the client answered. Nothing is rendered here. An expired quote gets the
  # business's usual validity from today, and an "update requested" is answered by the next send.
  def revise!(by:)
    transaction do
      lock!
      raise ArgumentError, "Quote #{number} can't be revised." unless revisable?

      snapshot = QuoteResponse.snapshot_of(self).merge(
        "files" => attachments_attachments.includes(:blob).map { { "blob_id" => _1.blob_id, "filename" => _1.filename.to_s } }
      )
      revisions.create!(business:, number: revision, snapshot:, status: expired? ? "expired" : status, pdf_blob_id:, sent_at:, revised_by: by)
      days = business.quote_expiry_days.to_i
      self.expires_on = business.today + days.days if past_expiry? && days.positive?
      assign_attributes(status: "draft", revision: revision + 1, update_requested_at: nil, pdf_blob_id: nil, pdf_digest: nil)
      save!(validate: false)
      QuoteEvent.record!(self, :revised, by:, revision:)
    end
  end

  # QTE-05: the client can approve, decline or ask for changes while the quote is sent and
  # still valid. A superseded revision can't be answered: its page now shows the latest, and
  # an answer posted from an old page fails the version check (Changed).
  def open_for_response? = sent? && !expired?

  def archived? = archived_at.present?

  # QTE-06: staff tidy the list. Archiving hides a quote from the list's other tabs; the client's
  # link keeps working.
  # Drafts aren't archived (delete them instead): only quotes that went out.
  def archivable? = !draft? && !archived?

  def archive!(by:)
    raise ArgumentError, "Delete a draft instead of archiving it." if draft?

    transaction { update_columns(archived_at: Time.current) && QuoteEvent.record!(self, :archived, by:) } unless archived?
  end

  def unarchive!(by:)
    transaction { update_columns(archived_at: nil) && QuoteEvent.record!(self, :unarchived, by:) } if archived?
  end

  # A sent quote that hasn't been answered (or the client asked for changes) can be given a new
  # valid-until date, including one that has already expired: any day from tomorrow to a year
  # out. The client's links are kept alive past it (PLT-12 grace), so "the same link" holds.
  def expiry_extendable? = status.in?(%w[sent changes_requested])
  MAX_VALIDITY = 1.year

  def extend_expiry!(date, by:)
    date = Date.parse(date.to_s) rescue nil # rubocop:disable Style/RescueModifier
    raise ArgumentError, "Choose a date after today." unless date && date > business.today
    raise ArgumentError, "Choose a date within a year." if date > business.today + MAX_VALIDITY

    transaction do
      lock!
      raise ArgumentError, "Only a sent quote's expiry can be extended." unless expiry_extendable?

      from = expires_on
      self.expires_on = date
      save!(validate: false)
      ClientLink.active.where(linkable: self).where("expires_at IS NOT NULL AND expires_at < ?", client_link_expires_at)
                .update_all(expires_at: client_link_expires_at)
      QuoteEvent.record!(self, :expiry_extended, by:, from: from&.iso8601, to: date.iso8601)
    end
  end

  # A new draft from this one: the lines, title, terms and discount. Numbers, dates, sends and
  # taxes start fresh (today's rates for the client). For the same client it keeps the
  # property, message, internal notes and files; for another client it keeps none of those,
  # since they're about the first client (their yard's photos, a gate code, "Hi Maria").
  def duplicate!(client: self.client, by: nil)
    same_client = client.id == client_id
    transaction do
      copy = Quote.start(client:, property: (property if same_client), created_by: by, location: (location unless location.archived?))
      copy.assign_attributes(title:, terms:, prices_include_tax:, discount_kind:, discount_percent:, discount_amount_cents:)
      copy.priced_for_location = pricing_location # CAT-08: copied prices; a different location offers its own
      copy.assign_attributes(message:, internal_notes:) if same_client
      copy.sync_line_items(BuiltDocument.rows_from(current_line_items))
      attachments.each { copy.attachments.attach(_1.blob) } if same_client
      copy.save!
      QuoteEvent.record!(copy, :duplicated, by:, from: number)
      copy
    end
  end

  # Staff can also record an approval after the client asked for changes (they agreed on the
  # phone after all), but not on an expired quote: its dates come first.
  def staff_can_approve? = status.in?(%w[sent changes_requested]) && !past_expiry?

  # Why a response was refused; the message is for the client page.
  class NotOpen < StandardError; end
  class Changed < StandardError; end

  # Records the client's answer (through `link`) or an approval staff record for the client
  # (`by`), and moves the quote to the matching status, once: the quote row is locked and must
  # still be open, so a double tap, a second device or a racing staff member records nothing
  # more. `version` is the lock_version the client's page showed; approving a quote that has
  # changed since is refused. Raises ActiveRecord::RecordInvalid for a missing name or note.
  RESPONSE_STATUS = { approve: "approved", decline: "declined", request_changes: "changes_requested" }.freeze
  def record_response!(action, link: nil, by: nil, version: nil, **attributes)
    kind = RESPONSE_STATUS.fetch(action.to_sym)
    transaction do
      lock!
      staff_approval = by && kind == "approved" && staff_can_approve?
      raise NotOpen, "This quote isn't open for a response." unless (open_for_response? || staff_approval) && !client.erased?
      raise Changed, "This quote was updated after you opened it." if version && version.to_i != lock_version

      response = responses.create!(business:, kind:, client_link: link, recorded_by: by, quote_version: lock_version, revision:, **attributes)
      # Only the status changes; the quote's content was frozen when it was sent, so its
      # validations aren't re-run (a rule added since mustn't block the client's answer).
      self.status = kind
      save!(validate: false)
      ClientEvent.record!(client, "quote_#{kind}", subject: self, by:, revision:, via: link && !by ? "client" : "staff") # CLI-05
      response
    end.tap { create_job_after_approval(by) if kind == "approved" }
  end

  # QTE-04: what the client sees is frozen from here on (changes after sending are revisions,
  # QTE-06). Records the send, and on the first one marks the quote sent and records the
  # billable "quote_sent" usage event exactly once (BIL-02). Returns the QuoteSend.
  # MKT-04: whether the last mark_sent! was the business's first quote ever sent.
  def first_quote_sent? = @first_quote_sent == true

  def mark_sent!(by:, channel:, recipient: nil, cc: nil, email_message: nil)
    transaction do
      lock!
      raise ArgumentError, "a #{status} quote can't be sent" unless draft? || sent?
      raise ArgumentError, "the client's details were erased" if client.erased? # INS-02

      update!(status: "sent", sent_at: Time.current, sent_by: by) if draft?
      # ACC-05: when the business sent its first quote, for time-to-first-quote (no PII).
      @first_quote_sent = Business.where(id: business_id, first_quote_sent_at: nil).update_all(first_quote_sent_at: Time.current) == 1
      UsageEvent.record!("quote_sent", self, at: sent_at || Time.current)
      ClientEvent.record!(client, :quote_sent, subject: self, by:, channel:, revision:) # CLI-05
      sends.create!(business:, user: by, channel:, recipient:, cc:, email_message:, revision:)
    end
  end

  # The link the client opens: the newest active one with at least a month left (so an emailed
  # link doesn't die soon after it's read), or a new one.
  # It lets the client answer the quote (QTE-05); older links without those actions are replaced.
  CLIENT_ACTIONS = %w[approve decline request_changes].freeze
  def client_link!
    link = ClientLink.active.where(linkable: self).where("actions @> ARRAY[?]::varchar[]", CLIENT_ACTIONS).order(created_at: :desc).first
    link && (link.expires_at.nil? || link.expires_at > 30.days.from_now) ? link : ClientLink.issue!(self, actions: CLIENT_ACTIONS)
  end

  # Whether it can go out: it needs something to quote, and a valid-until date that hasn't
  # passed (an expired quote is renewed with a revision, QTE-06).
  def sendable? = (draft? || sent?) && line_items.any? && !past_expiry? && !client.erased?

  # BIL-02/03: whether sending it now counts toward the plan's quotes: its first send only
  # (resends and revisions of a quote that went out never count).
  def counts_toward_usage? = draft? && sends.none?
  def past_expiry? = expires_on.present? && expires_on < business.today

  # Clients only ever see quotes that were sent (QTE-03): a draft is never reachable.
  def client_visible? = !draft?
  # The client page itself also opens while a new revision is being prepared (QTE-06).
  def client_page_visible? = client_visible? || revising?

  # What the client page says about the quote.
  def client_state
    return :revising if revising?
    return status.to_sym if status.in?(%w[draft approved declined changes_requested])
    return :expired if expired?

    :awaiting
  end

  def expired? = past_expiry? && status == "sent"

  # QTE-02: the PDF. Sent quotes keep theirs (the same file until something on it changes);
  # drafts are rendered fresh for staff.
  def pdf_html = PdfDocument.render("pdfs/quote", quote: self, business:)
  def pdf_filename = "Quote #{number}.pdf"
  def pdf_paper = PdfRenderer.paper_for(business.country)
  def store_pdf? = !draft?
  # What a stored PDF must match: the template version (bump PDF_VERSION to replace stored files
  # after a template fix), the quote's own content (any saved edit bumps lock_version) and status,
  # and the client and property it names. Not the letterhead or the expiry date: a sent PDF
  # keeps the business's details as sent, and says "Valid until" either way.
  PDF_VERSION = 1
  def pdf_fingerprint
    [ PDF_VERSION, id, lock_version, status, client.updated_at.to_f, property&.updated_at.to_f ].join(":")
  end

  # Make the PDF when a quote is sent or answered, ahead of the first download.
  after_commit -> { QuotePdfJob.perform_later(business_id, id) }, on: :update, if: -> { saved_change_to_status? && store_pdf? }

  def pdf_footer
    %(<div style="width:100%;margin:0 0.55in;display:flex;justify-content:space-between;font:7.5pt sans-serif;color:#64748b">) +
      %(<span>#{ERB::Util.h(business.name)}, quote #{ERB::Util.h(number)}</span>) +
      %(<span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>)
  end

  # The status in words, for the document. From the status alone, so a sent quote's stored PDF
  # doesn't change when its date passes (the client page shows expiry separately).
  STATUS_LABELS = { "draft" => "Draft", "sent" => "Awaiting approval", "approved" => "Approved", "declined" => "Declined",
                    "changes_requested" => "Changes requested" }.freeze
  def state_label = STATUS_LABELS.fetch(status)
  def client_state_label = client_state == :expired ? "Expired" : state_label

  # PLT-12: the partial client links render for a quote.
  def client_link_partial = "client/quotes/quote"

  # PLT-12: a quote's link outlives the quote by a month, so an expired quote can still be
  # seen and an update asked for; never less than the default link lifetime.
  CLIENT_LINK_GRACE = 30.days
  def client_link_expires_at
    default = ClientLink::DEFAULT_LIFETIME.from_now
    return default unless expires_on

    [ expires_on.in_time_zone(business.time_zone).end_of_day + CLIENT_LINK_GRACE, default ].max
  end

  # Starts a draft for a client with the business's defaults: next number, expiry, terms,
  # and the tax rates new documents get (none for a tax-exempt client).
  # QTE-07: the drafts someone who quotes their assigned requests may open: ones they made from a
  # request, never sent (a sent quote revised by the office is a draft again, but not theirs).
  def self.own_drafts_for(user) = where(created_by_id: user.id, status: "draft", revision: 1).where.not(service_request_id: nil)

  def self.start(client:, property: nil, created_by: nil, location: nil)
    create!(client:, property: property || client.billing_property || client.properties.first, created_by:, location:)
  end

  private

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:quote)
    self.currency ||= business.currency_code
    self.expires_on ||= business.today + business.quote_expiry_days.to_i.days if business.quote_expiry_days.to_i.positive?
    self.terms ||= business.quote_terms
    self.tax_rate_list = TaxRate.for_new_document(client:, location:) if tax_rates.blank?
  end

  # JOB-01: an approved quote becomes a job when the business has that on (the default). It
  # runs once the approval has committed (a client's approval runs inside the link's
  # transaction), so it can never undo the answer or hold its locks; if it fails, staff can
  # still make the job from the quote page. Expected refusals (an archived client) aren't errors.
  def create_job_after_approval(by)
    return unless business.auto_create_jobs

    ActiveRecord.after_all_transactions_commit do
      Tenancy.with_business(business) { Job.from_quote!(self, by:) }
    rescue ActiveRecord::RecordInvalid, Job::NotOpen => e
      Rails.logger.info("No automatic job for quote #{id}: #{e.message}")
    rescue StandardError => e
      Rails.error.report(e, context: { quote_id: id })
    end
  end

  def property_belongs_to_client
    errors.add(:property, "must be one of this client's properties") if property && client && property.client_id != client.id
  end

  def location_source = service_request
end
