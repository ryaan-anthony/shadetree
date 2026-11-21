# An invoice for a client (PAY-01): made from a job (its items), from an approved quote, or from
# scratch. It prices exactly like a quote (PricedDocument, BuiltDocument and DocumentLine are
# shared, PLT-08) and adds what billing needs: an issue date, payment terms and the due date
# they give, and the amount paid so far.
#
# Statuses: draft → sent (PAY-02) → partially_paid → paid (payments, PAY-04/PAY-05), or void.
# Overdue isn't a status: it's a sent or partly paid invoice whose due date has passed, for the
# business's today. Each change of status is recorded as an InvoiceEvent.
class Invoice < ApplicationRecord
  include BusinessOwned
  include AtLocation # CAT-07
  include LocationRepricing # CAT-08
  include PricedDocument
  include BuiltDocument
  include DocumentAttachments
  include HasPdf
  include EmailedDocument # QTE-04, PAY-02: delivery warnings

  STATUSES = %w[draft sent partially_paid paid void].freeze
  STATUS_LABELS = { "draft" => "Draft", "sent" => "Sent", "partially_paid" => "Partly paid", "paid" => "Paid", "void" => "Void" }.freeze
  # Unpaid and not void: what the business is still owed.
  OUTSTANDING = %w[sent partially_paid].freeze

  # Payment terms and the days they give; "custom" is a due date chosen on the invoice.
  TERMS = { "due_on_receipt" => 0, "net_7" => 7, "net_15" => 15, "net_30" => 30, "custom" => nil }.freeze
  TERM_LABELS = { "due_on_receipt" => "Due on receipt", "net_7" => "Net 7", "net_15" => "Net 15", "net_30" => "Net 30",
                  "custom" => "Custom date" }.freeze

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  belongs_to_business_record :job, optional: true
  belongs_to_business_record :quote, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  belongs_to :voided_by, class_name: "User", optional: true
  has_many :line_items, -> { order(:position, :id) }, class_name: "InvoiceLineItem", inverse_of: :invoice,
           dependent: :delete_all, autosave: true
  has_many :events, -> { order(:occurred_at, :id) }, class_name: "InvoiceEvent", inverse_of: :invoice, dependent: :delete_all
  has_many :revisions, -> { order(:number) }, class_name: "InvoiceRevision", inverse_of: :invoice, dependent: :delete_all
  has_many :payments, -> { chronological }, inverse_of: :invoice, dependent: :restrict_with_exception # PAY-05
  has_many :sends, -> { recent }, class_name: "InvoiceSend", inverse_of: :invoice, dependent: :delete_all
  has_many :email_messages, as: :related, dependent: :nullify

  normalizes :title, with: ->(value) { value.to_s.squish.presence }
  normalizes :message, :internal_notes, :terms, with: ->(value) { value.to_s.strip.presence }

  validates :number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_terms, inclusion: { in: TERMS.keys }
  validates :issued_on, :due_on, presence: true
  validates :title, length: { maximum: 120 }
  validates :void_reason, length: { maximum: 200 }
  validates :message, :terms, :internal_notes, length: { maximum: 5_000 }
  validate { errors.add(:due_on, "can't be before the issue date") if due_on && issued_on && due_on < issued_on }
  validate :belongs_with_client

  # Prices copied or typed into a new invoice's lines need its currency before it's saved.
  after_initialize { self.currency ||= (business || Current.business)&.currency_code if new_record? }
  before_validation :assign_number_and_defaults, on: :create
  before_validation :apply_payment_terms

  # A new draft for a client, with the business's defaults (terms, due date, taxes).
  class NotApproved < StandardError; end

  def self.start(client:, property: nil, created_by: nil, location: nil)
    transaction { create!(client:, property: property || client.primary_property, created_by:, location:).tap { _1.record!(:created, by: created_by) } }
  end

  # PAY-01: the job's work, billed: its client, property, items, discount and taxes. The job's
  # quote (if any) is linked too. A job can be invoiced more than once (progress billing).
  def self.from_job!(job, by: nil)
    transaction do
      invoice = new(client: job.client, property: job.property, job:, quote: job.quote, created_by: by, title: job.title, currency: job.currency)
      invoice.copy_pricing_from(job)
      invoice.save!
      invoice.record!(:created, by:, from: "job", number: job.number)
      invoice
    end
  end

  # PAY-01: an approved quote, billed as agreed (the quote's lines, not the job's on-site
  # changes). Its job is linked when there is one.
  def self.from_quote!(quote, by: nil)
    raise NotApproved, "Only an approved quote can be invoiced." unless quote.approved?

    transaction do
      invoice = new(client: quote.client, property: quote.property, quote:, job: quote.job, created_by: by, title: quote.title, currency: quote.currency)
      invoice.copy_pricing_from(quote)
      invoice.save!
      invoice.record!(:created, by:, from: "quote", number: quote.number)
      invoice
    end
  end

  def copy_pricing_from(document)
    assign_attributes(tax_rates: document.tax_rates, prices_include_tax: document.prices_include_tax,
                      discount_kind: document.discount_kind, discount_percent: document.discount_percent,
                      discount_amount_cents: document.discount_amount_cents)
    sync_line_items(BuiltDocument.rows_from(document.current_line_items))
  end

  def draft? = status == "draft"
  def void? = status == "void"
  def awaiting_client? = status.in?(%w[sent partially_paid])
  def paid? = status == "paid"
  def status_label = revising? ? "Revising" : STATUS_LABELS.fetch(status)
  def terms_label = TERM_LABELS.fetch(payment_terms)

  # Drafts are edited freely, including a sent invoice reopened as its next revision. Once
  # anything is paid, an invoice can't be revised or voided (its items can't change).
  def editable? = draft?
  def payments? = amount_paid_cents.positive?

  # A sent invoice being revised: a draft again, as revision N+1, until it's sent again (PAY-02).
  def revising? = draft? && revision > 1

  def revisable? = status == "sent" && !payments?

  # PAY-02: a draft (or a revision being prepared) goes out once it has something to bill;
  # an unpaid sent invoice can be sent again. Paid and void ones aren't sent.
  def sendable? = status.in?(%w[draft sent partially_paid]) && line_items.any? && !client.erased?

  # The issue and due dates it goes out with. A draft first sent after its issue date is issued
  # today, its due date following its terms (a custom date keeps its distance from the issue
  # date, as in the builder), so an invoice never goes out already overdue. Revisions keep
  # their dates.
  def dates_when_sent(today = business.today)
    return [ issued_on, due_on ] if sent_at || issued_on.nil? || issued_on >= today

    due = payment_terms == "custom" ? due_on && due_on + (today - issued_on) : due_on_for(payment_terms, today)
    [ today, [ due, today ].compact.max ]
  end

  # Records a send by email or link. The first send of a draft, or of a revision, marks it
  # sent (who and when; the revision is now what the client has). Returns the InvoiceSend.
  def mark_sent!(by:, channel:, recipient: nil, cc: nil)
    transaction do
      lock!
      raise ArgumentError, "Invoice #{number} can't be sent." unless sendable? && !client.erased? # INS-02

      if draft?
        issued, due = dates_when_sent
        update!(status: "sent", sent_at: Time.current, sent_by: by, issued_on: issued, due_on: due)
      end
      record!(:sent, by:, channel:, revision:)
      ClientEvent.record!(client, :invoice_sent, subject: self, by:, channel:, revision:) # CLI-05
      sends.create!(business:, user: by, channel:, recipient:, cc:, revision:)
    end
  end

  # Keeps what the client was sent as revision N and reopens the invoice as the draft of
  # revision N+1. Its link keeps working; PAY-02's client page says it's being updated.
  def revise!(by:)
    transaction do
      lock!
      raise ArgumentError, "Invoice #{number} can't be revised: #{payments? ? "it has payments" : "only a sent invoice can"}." unless revisable?

      revisions.create!(business:, number: revision, snapshot:, status:, sent_at:, pdf_blob_id:, revised_by: by, created_at: Time.current)
      assign_attributes(status: "draft", revision: revision + 1, pdf_blob_id: nil, pdf_digest: nil)
      save!(validate: false)
      record!(:revised, by:, revision:)
      close_checkout_later # PAY-04: the client can't pay the old version meanwhile
    end
  end

  # Drops a revision being prepared: the invoice is again exactly what the client was sent
  # (lines, dates, terms, files and its PDF), and that revision's record is removed. Voiding a
  # revising invoice does this first, so the client never sees the unfinished edits.
  def discard_revision!(by:)
    transaction do
      lock!
      raise ArgumentError, "Invoice #{number} isn't being revised." unless revising?

      previous = revisions.last
      restore_snapshot(previous.snapshot)
      assign_attributes(status: previous.status, revision: previous.number, pdf_blob_id: previous.pdf_blob_id, pdf_digest: nil)
      save!(validate: false)
      previous.destroy!
      record!(:revision_discarded, by:, revision: previous.number + 1)
    end
  end

  # Cancels an invoice that went out, with a reason; it stays on record, numbered, as Void. A
  # draft that never went out is deleted instead, and one with payments can't be voided (record
  # the money back first, PAY-05). Void and reissue is how a sent invoice is corrected at launch.
  def voidable? = !void? && sent_at.present? && !payments?

  def void!(reason:, by:)
    reason = reason.to_s.squish
    raise ArgumentError, "Say why it's being voided." if reason.empty?

    transaction do
      lock!
      discard_revision!(by:) if revising?
      raise ArgumentError, "Invoice #{number} can't be voided#{" while it has payments" if payments?}." unless voidable?

      # Skips validation, as revise! does: an old row that no longer validates can still be voided.
      assign_attributes(status: "void", voided_at: Time.current, voided_by: by, void_reason: reason.first(200))
      save!(validate: false)
      record!(:voided, by:, reason: void_reason)
      close_checkout_later # PAY-04
    end
  end

  # What the client was sent, for the revision record.
  def snapshot
    {
      "title" => title, "issued_on" => issued_on.iso8601, "due_on" => due_on.iso8601, "payment_terms" => payment_terms,
      "message" => message, "terms" => terms, "currency" => currency, "tax_rates" => tax_rates, "prices_include_tax" => prices_include_tax,
      "discount" => discount_value&.to_s, "discount_kind" => discount_kind, "subtotal_cents" => subtotal_cents, "tax_cents" => tax_cents,
      "total_cents" => total_cents,
      "lines" => current_line_items.map { _1.attributes.slice(*%w[name description quantity unit unit_price_cents taxable discount_kind]).merge("discount" => _1.discount_value&.to_s) },
      "files" => attachments_attachments.includes(:blob).map { { "blob_id" => _1.blob_id, "filename" => _1.filename.to_s } }
    }
  end

  # PAY-01: completion photos from the job's visits (JOB-04), by attachment id. Only the job's
  # own photos, and each once; the invoice shares the stored file.
  def job_photos = job ? ActiveStorage::Attachment.where(record_type: "Visit", name: "photos", record_id: job.visits.select(:id)).includes(:blob).order(:created_at) : ActiveStorage::Attachment.none

  def attach_job_photos(ids)
    attached = attachments_attachments.map(&:blob_id)
    job_photos.where(id: Array(ids).compact_blank).each do |photo|
      next if attached.include?(photo.blob_id)

      attachments.attach(photo.blob)
      attached << photo.blob_id
    end
  end

  def outstanding? = OUTSTANDING.include?(status)
  def overdue?(today = business.today) = outstanding? && due_on < today

  def amount_paid = Money.new(amount_paid_cents, currency)
  def balance = Money.new([ total_cents - amount_paid_cents, 0 ].max, currency)

  # The due date a choice of terms gives, from the issue date ("custom" keeps the one chosen).
  def due_on_for(terms, issued = issued_on)
    days = TERMS[terms]
    days && issued ? issued + days : due_on
  end

  # A draft that was never sent can be deleted; anything sent is voided instead (part 2).
  def deletable? = draft? && sent_at.nil?

  # PAY-05: payments. One can be recorded on a sent invoice with a balance, or on a draft (paid
  # on the spot: recording marks it sent too), but not on a revision being prepared.
  def payable? = (status.in?(OUTSTANDING) || (draft? && !revising?)) && total_cents.positive? && line_items.any?

  # Records a cash, check, transfer or other payment. Returns the Payment; if it isn't valid
  # (or is more than the balance) nothing changes and the errors are on it.
  def record_payment!(by:, **attributes)
    transaction do
      lock!
      payment = payments.new(business:, currency:, source: "recorded", recorded_by: by)
      payment.assign_attributes(attributes)
      raise ArgumentError, "Invoice #{number} can't take a payment now." unless payable?
      return payment unless payment_fits?(payment, available: balance.cents)

      if draft?
        issued, due = dates_when_sent
        update!(status: "sent", sent_at: Time.current, sent_by: by, issued_on: issued, due_on: due)
        record!(:sent, by:, channel: "payment", revision:)
        ClientEvent.record!(client, :invoice_sent, subject: self, by:, channel: "payment", revision:) # CLI-05
      end
      payment.save!
      close_checkout_later # PAY-04: the balance changed under an open Checkout page
      record!(:payment_recorded, by:, payment: payment.uid, **payment.summary)
      ClientEvent.record!(client, :payment_recorded, subject: payment, by:, **payment.summary) # CLI-05
      apply_payments!(by:)
      payment
    end
  end

  # PAY-04: whether the client can pay online now, from the invoice's link: something left to
  # pay on a sent invoice (not one being revised, a void one or an erased client's), at least
  # Stripe's smallest charge, and a business whose Stripe account takes charges.
  ONLINE_MINIMUM_CENTS = 50
  def online_payable? = outstanding? && balance.cents >= ONLINE_MINIMUM_CENTS && !client.erased? && business.active? && business.accepts_online_payments?

  # PAY-04: a payment Stripe confirmed (checkout.session.completed or payment_intent.succeeded).
  # Recorded once per PaymentIntent, whichever notification comes first; the money has been
  # taken, so it's recorded even if the invoice changed meanwhile: a revision being prepared is
  # dropped (the client paid what they were sent), and a void invoice keeps its status. What
  # Stripe already knows about the charge (refunded, disputed) comes with it, so an earlier
  # refund or dispute notification isn't lost. Returns [payment, new?, overpaid_cents].
  def record_online_payment!(intent_id:, amount_cents:, currency:, received_on: business.today, checkout_id: nil, method_detail: nil,
                             platform_fee_cents: 0, refunded_cents: 0, dispute: nil)
    transaction do
      lock!
      existing = Payment.find_by(provider_payment_id: intent_id)
      next [ existing, false, 0 ] if existing

      discard_revision!(by: nil) if revising?
      # This payment's Checkout page is done; another one still open is for an old balance.
      checkout_session_id == checkout_id ? clear_checkout : close_checkout_later
      owed = void? ? 0 : balance.cents
      payment = payments.create!(business:, source: "online", payment_method: "card", amount_cents:, currency: currency.upcase,
                                 received_on:, reference: intent_id, provider_payment_id: intent_id,
                                 provider_checkout_id: checkout_id, method_detail:, platform_fee_cents:,
                                 refunded_cents: refunded_cents.to_i.clamp(0, amount_cents),
                                 dispute_status: dispute&.fetch("status"), disputed_cents: dispute ? dispute["amount_cents"].to_i.clamp(0, amount_cents) : 0)
      record!(:payment_received, payment: payment.uid, **payment.summary)
      ClientEvent.record!(client, :payment_recorded, subject: payment, by: nil, via: "client", **payment.summary) # CLI-05, NTF-04 payment_received
      apply_payments!
      [ payment, true, [ amount_cents - owed, 0 ].max ]
    end
  end

  # PAY-04: the Checkout page open for this invoice, if it can still be paid for a while.
  def open_checkout?(within: 5.minutes) = checkout_session_id.present? && checkout_expires_at.present? && checkout_expires_at > within.from_now

  def remember_checkout!(session, amount_cents:, expires_at:)
    update_columns(checkout_session_id: session.fetch("id"), checkout_session_url: session.fetch("url"), checkout_amount_cents: amount_cents,
                   checkout_expires_at: expires_at)
  end

  def clear_checkout = update_columns(checkout_session_id: nil, checkout_session_url: nil, checkout_amount_cents: nil, checkout_expires_at: nil)

  # Closes the open Checkout page once this change commits (a payment recorded, voided, revised),
  # so it can't be paid for an amount that's no longer right.
  def close_checkout_later
    return unless (session_id = checkout_session_id)

    clear_checkout
    ActiveRecord.after_all_transactions_commit { ExpireCheckoutSessionJob.perform_later(id, session_id) }
  end

  # PAY-04: refunds and disputes on an online payment, as Stripe reports them (cumulative, so a
  # repeat changes nothing). The invoice follows: a refund can take it back to Partly paid or
  # Sent. Returns the payment and whether that reopened the invoice (OnlinePayments warns).
  def reflect_refund!(payment, refunded_cents:)
    adjust_online_payment(payment, :payment_refunded) { payment.refunded_cents = refunded_cents.clamp(0, payment.amount_cents) }
  end

  def reflect_dispute!(payment, status:, amount_cents:)
    adjust_online_payment(payment, :payment_disputed) { payment.assign_attributes(dispute_status: status, disputed_cents: amount_cents.clamp(0, payment.amount_cents)) }
  end

  # Corrects a recorded payment, with a reason; the history keeps what it was.
  def change_payment!(payment, by:, reason:, **attributes)
    adjust_payment(payment, by:, reason:) do
      before = payment.summary
      payment.assign_attributes(attributes)
      next payment unless payment_fits?(payment, available: balance.cents + payment.amount_cents_was.to_i)

      payment.save!
      record!(:payment_changed, by:, payment: payment.uid, reason: reason.to_s.squish.first(200), before:, after: payment.summary)
      ClientEvent.record!(client, :payment_changed, subject: payment, by:, before:, after: payment.summary) # CLI-05
      payment
    end
  end

  def delete_payment!(payment, by:, reason:)
    adjust_payment(payment, by:, reason:) do
      payment.destroy!
      record!(:payment_deleted, by:, payment: payment.uid, reason: reason.to_s.squish.first(200), **payment.summary)
      ClientEvent.record!(client, :payment_deleted, subject: self, by:, **payment.summary) # CLI-05
      payment
    end
  end

  # The amount paid, status and paid time from the payments: Paid once they cover the total
  # (paid_at: then), Partly paid, or back to Sent. Active client links follow (PLT-12): a year
  # after payment once it's paid, no end while it isn't.
  def apply_payments!(by: nil)
    # PAY-04: refunds and lost disputes don't count as paid. A void invoice stays void; only
    # its amount paid follows (money taken online after it was voided).
    paid_cents = payments.unscope(:order).counted_sum.to_i
    return update_columns(amount_paid_cents: paid_cents, updated_at: Time.current) if void?

    status = if paid_cents >= total_cents then "paid" elsif paid_cents.positive? then "partially_paid" else "sent" end
    changed = status != self.status
    assign_attributes(amount_paid_cents: paid_cents, status:, paid_at: (status == "paid" ? (paid_at || Time.current) : nil))
    save!(validate: false)
    record!({ "paid" => :paid, "partially_paid" => :partially_paid, "sent" => :reopened }.fetch(status), by:) if changed
    # CLI-05: paid in full, and no longer (a payment changed or deleted).
    ClientEvent.record!(client, :invoice_paid, subject: self, by:) if changed && status == "paid"
    ClientEvent.record!(client, :invoice_unpaid, subject: self, by:) if changed && status_previously_was == "paid"
    ClientLink.active.where(linkable: self).update_all(expires_at: client_link_expires_at)
  end

  def record!(kind, by: nil, **data) = InvoiceEvent.record!(self, kind, by:, **data)

  # The list's tabs. Overdue and awaiting payment depend on the business's today.
  FILTERS = { "all" => "All", "outstanding" => "Awaiting payment", "overdue" => "Overdue", "draft" => "Drafts", "paid" => "Paid",
              "void" => "Void" }.freeze
  def self.filtered(filter, today:)
    case filter
    when "all" then all
    when "outstanding" then where(status: OUTSTANDING)
    when "overdue" then where(status: OUTSTANDING).where(due_on: ...today)
    else where(status: filter)
    end
  end

  # How many invoices each tab holds, in one query.
  def self.filter_counts(today:)
    counts = group(:status).group(Arel.sql(sanitize_sql_array([ "invoices.due_on < ?", today ]))).count
    by_status = counts.each_with_object(Hash.new(0)) { |((status, _), count), sums| sums[status] += count }
    overdue = counts.sum { |(status, late), count| OUTSTANDING.include?(status) && late ? count : 0 }
    { "all" => by_status.values.sum, "outstanding" => OUTSTANDING.sum { by_status[_1] }, "overdue" => overdue,
      "draft" => by_status["draft"], "paid" => by_status["paid"], "void" => by_status["void"] }
  end

  # What's owed on the outstanding invoices in a scope, per currency, and how much of it is overdue.
  def self.owed(today:)
    outstanding = where(status: OUTSTANDING)
    sum_by = ->(scope) { scope.group(:currency).sum(Arel.sql("GREATEST(invoices.total_cents - invoices.amount_paid_cents, 0)")).map { |currency, cents| Money.new(cents.to_i, currency) } }
    { outstanding: sum_by.(outstanding), overdue: sum_by.(outstanding.where(due_on: ...today)) }
  end

  # PAY-02: what the client sees. A draft never (QTE-03's rule); a sent invoice being revised
  # shows "being updated" on its page, without the unfinished edits.
  def client_visible? = !draft?
  def client_page_visible? = client_visible? || revising?
  def client_link_partial = "client/invoices/invoice"

  # The link the client opens: one that doesn't expire while the invoice is unpaid, so a client
  # can always find what they owe; it's given an end a year after payment (PAY-04/PAY-05).
  CLIENT_LINK_AFTER_PAID = 1.year
  def client_link!
    ClientLink.active.where(linkable: self).order(created_at: :desc).first || ClientLink.issue!(self)
  end

  def client_link_expires_at
    case status
    when "paid" then (paid_at || updated_at) + CLIENT_LINK_AFTER_PAID
    when "void" then (voided_at || updated_at) + CLIENT_LINK_AFTER_PAID
    end
  end

  # PAY-02: the PDF (QTE-02's approach): sent invoices keep theirs until something on it
  # changes, including a payment (its balance); drafts are rendered fresh.
  def pdf_html = PdfDocument.render("pdfs/invoice", invoice: self, business:)
  def pdf_filename = "Invoice #{number}.pdf"
  def pdf_paper = PdfRenderer.paper_for(business.country)
  def store_pdf? = !draft?
  PDF_VERSION = 1
  def pdf_fingerprint
    [ PDF_VERSION, id, lock_version, status, amount_paid_cents, client.updated_at.to_f, property&.updated_at.to_f ].join(":")
  end

  def pdf_footer
    %(<div style="width:100%;margin:0 0.55in;display:flex;justify-content:space-between;font:7.5pt sans-serif;color:#64748b">) +
      %(<span>#{ERB::Util.h(business.name)}, invoice #{ERB::Util.h(number)}</span>) +
      %(<span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>)
  end

  # The status in words, for the client: from the status and balance alone, so a stored PDF
  # doesn't change when the due date passes (the page shows overdue separately).
  def client_state_label
    case status
    when "paid" then "Paid"
    when "void" then "Void"
    when "partially_paid" then "Partly paid"
    else "Unpaid"
    end
  end

  # By invoice number, or by client (name, phone, email or address, as CLI-02 searches).
  def self.search(query)
    query = query.to_s.strip
    return all if query.empty?

    where("invoices.number ILIKE ?", "%#{sanitize_sql_like(query)}%").or(where(client_id: Client.search(query).select(:id)))
  end

  private

  # A payment can't be more than what's owed on the invoice.
  def payment_fits?(payment, available:)
    return false unless payment.valid?

    if payment.amount_cents > available
      payment.errors.add(:amount, "is more than the #{payments? ? "balance" : "amount due"} (#{Money.new(available, currency).format})")
      return false
    end
    true
  end

  # Changing or deleting a payment: only recorded ones, only on a sent invoice, with a reason.
  def adjust_payment(payment, by:, reason:)
    raise ArgumentError, "Say why." if reason.to_s.squish.empty?

    transaction do
      lock!
      payment.lock!
      raise ArgumentError, "Online payments can't be changed here." if payment.online?
      raise ArgumentError, "Invoice #{number} is void." if void?

      result = yield
      apply_payments!(by:) if result.errors.empty?
      result
    end
  end

  def adjust_online_payment(payment, kind)
    transaction do
      lock!
      payment.lock!
      yield
      next [ payment, false ] unless payment.changed?

      counted_before = payment.counted_cents_was
      payment.save!
      record!(kind, payment: payment.uid, refunded_cents: payment.refunded_cents, dispute: payment.dispute_status, **payment.summary)
      apply_payments!
      [ payment, outstanding? && payment.counted_cents < counted_before ]
    end
  end

  # Puts back what a revision recorded (Invoice#snapshot), for discard_revision!.
  def restore_snapshot(data)
    assign_attributes(data.slice(*%w[title issued_on due_on payment_terms message terms tax_rates prices_include_tax]))
    set_discount(data["discount_kind"], data["discount"])
    lines = data["lines"].map { _1.slice(*%w[name description quantity unit taxable discount_kind]).merge("key" => SecureRandom.uuid, "discount_value" => _1["discount"]) }
    sync_line_items(lines).zip(data["lines"]) { |item, line| item.unit_price_cents = line["unit_price_cents"] }
    kept = data["files"].pluck("blob_id")
    attachments_attachments.each do |file|
      next if kept.include?(file.blob_id)

      # A file another revision recorded, or that's shared (a visit photo), only loses this link.
      recorded = revisions.any? { |revision| revision.snapshot["files"].to_a.any? { _1["blob_id"] == file.blob_id } }
      shared = ActiveStorage::Attachment.where(blob_id: file.blob_id).where.not(id: file.id).exists?
      recorded || shared ? file.delete : file.purge_later
    end
    present = attachments_attachments.map(&:blob_id)
    ActiveStorage::Blob.where(id: kept - present).each { attachments.attach(_1) }
  end

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:invoice)
    self.currency ||= business.currency_code
    self.issued_on ||= business.today
    self.terms ||= business.invoice_terms
    self.tax_rate_list = TaxRate.for_new_document(client:, location:) if tax_rates.blank? && job.nil? && quote.nil?
    return if payment_terms_changed? # chosen

    days = business.invoice_due_days.to_i
    self.payment_terms = TERMS.key(days) || "custom"
    self.due_on ||= issued_on + days
  end

  # Terms other than "custom" set the due date from the issue date.
  # Fixed terms give the due date from the issue date. A custom date (also what a business's
  # own number of days, like 45, starts as) keeps its distance from the issue date when only
  # the issue date moves.
  def apply_payment_terms
    if TERMS[payment_terms] && issued_on
      self.due_on = due_on_for(payment_terms)
    elsif issued_on_changed? && issued_on_was && issued_on && due_on && !due_on_changed?
      self.due_on = due_on + (issued_on - issued_on_was)
    end
  end

  def belongs_with_client
    return unless client

    errors.add(:property, "must be one of this client's properties") if property && property.client_id != client_id
    errors.add(:job, "must be for the same client") if job && job.client_id != client_id
    errors.add(:quote, "must be for the same client") if quote && quote.client_id != client_id
  end

  def location_source = job || quote
end
