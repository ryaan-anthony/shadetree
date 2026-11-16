# The client's answer to a sent quote (QTE-05): approved, declined or changes requested. A
# client answers through their link; Owners and Admins can record an approval the client gave
# another way (a phone call), with a required note. Rows are evidence and never change.
#
# An approval keeps a snapshot of exactly what was approved (lines, prices, taxes, totals,
# terms) and its SHA-256 digest, so later edits elsewhere (a client renamed, a catalog price
# changed) can't blur what the client agreed to.
class QuoteResponse < ApplicationRecord
  include BusinessOwned

  KINDS = %w[approved declined changes_requested].freeze
  MESSAGE_MAX = 2_000

  belongs_to_business_record :quote
  belongs_to :client_link, optional: true
  belongs_to :recorded_by, class_name: "User", optional: true

  normalizes :signer_name, with: ->(value) { value.to_s.squish.presence }
  normalizes :email, with: ->(value) { value.to_s.strip.downcase.presence }
  normalizes :message, with: ->(value) { value.to_s.strip.presence }

  validates :kind, inclusion: { in: KINDS }
  validates :signer_name, presence: true, length: { maximum: 120 }, if: -> { approved? && !on_behalf? }
  validates :signer_name, presence: { message: "Add who approved." }, length: { maximum: 120 }, if: -> { approved? && on_behalf? }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: "doesn't look like an email address" }, length: { maximum: 254 }, allow_nil: true
  validates :message, length: { maximum: MESSAGE_MAX }
  validates :message, presence: { message: "Say what you'd like changed." }, if: -> { kind == "changes_requested" }
  validates :message, presence: { message: "Add a note about how the client approved." }, if: -> { approved? && on_behalf? }
  validates :terms_accepted, acceptance: { accept: [ "1", true ], allow_nil: false }, on: :create, if: -> { approved? && !on_behalf? }

  attr_accessor :terms_accepted

  before_create :capture_snapshot, if: :approved?
  before_create :sign
  after_create_commit :notify

  def readonly? = persisted?
  def approved? = kind == "approved"
  def on_behalf? = recorded_by_id.present? || recorded_by.present?

  LABELS = { "approved" => "Approved", "declined" => "Declined", "changes_requested" => "Changes requested" }.freeze
  def label = LABELS.fetch(kind)

  # Everything the client saw that a price depends on, from the quote as it stands now (inside
  # the locked transaction that records the response).
  def self.snapshot_of(quote)
    totals = quote.totals
    {
      "number" => quote.number, "title" => quote.title, "version" => quote.lock_version, "currency" => quote.currency,
      "client" => quote.client.display_name, "property" => quote.property&.address_lines,
      "sent_at" => quote.sent_at&.iso8601, "expires_on" => quote.expires_on&.iso8601, "message" => quote.message,
      "prices_include_tax" => quote.prices_include_tax, "tax_rates" => quote.tax_rates,
      "discount" => { "kind" => quote.discount_kind, "value" => quote.discount_value&.to_s },
      "lines" => quote.current_line_items.each_with_index.map do |line, index|
        { "name" => line.name, "description" => line.description, "quantity" => line.quantity.to_d.to_s("F"), "unit" => line.unit,
          "unit_price_cents" => line.unit_price_cents, "taxable" => line.taxable, "discount_kind" => line.discount_kind,
          "discount_value" => line.discount_value&.to_s, "amount_cents" => totals.lines[index].subtotal.cents }
      end,
      # In cents, as computed for the client page and PDF (Pricing::DocumentTotals).
      "totals" => { "subtotal_cents" => totals.subtotal.cents, "discount_cents" => quote.discount_total_cents,
                    "tax_cents" => totals.tax_total.cents, "total_cents" => totals.total.cents },
      "terms" => quote.terms
    }
  end

  # Over canonical JSON (keys sorted at every level): jsonb stores keys in its own order, so
  # the digest must not depend on it.
  def self.digest(snapshot) = OpenSSL::Digest::SHA256.hexdigest(JSON.generate(canonical(snapshot)))

  def self.canonical(value)
    case value
    when Hash then value.to_h { |key, item| [ key.to_s, canonical(item) ] }.sort.to_h
    when Array then value.map { canonical(_1) }
    else value
    end
  end

  # Whether the stored snapshot still matches its digest (it can't change through the app;
  # this is for anyone checking the evidence).
  def snapshot_intact? = snapshot.present? && self.class.digest(snapshot) == snapshot_digest

  # Whether the record is as it was written: an HMAC (keyed from secret_key_base) over who,
  # when, from where and what. Someone editing the database alone can't make it verify.
  def signature_valid? = signature.present? && ActiveSupport::SecurityUtils.secure_compare(signature, compute_signature)

  # A short reference for the approval, shown to the client (PDF, email) and staff.
  def reference = signature.to_s.first(12).upcase.scan(/.{4}/).join("-")

  # The email the client's approval confirmation goes to: the one typed at approval, or the
  # client's own.
  def confirmation_email = email || quote.client.primary_email&.value

  private

  # The team hears about every response; a client who approved gets a confirmation (not when
  # staff recorded the approval for them).
  def notify
    QuoteActivityMailer.deliver_later_for(self)
    return unless approved? && !on_behalf? && (to = confirmation_email)
    return if EmailMessage.hourly_limit_reached? # the approval stands; only the copy is skipped

    QuoteMailer.send_later(:approved, business:, to:, kind: "quote_approved", related: quote, quote_id: quote.id)
  end

  def sign
    self.created_at ||= Time.current.floor(6) # stored to the microsecond, so it reads back the same
    self.signature = compute_signature
  end

  def compute_signature
    evidence = {
      "quote" => quote.uid, "number" => quote.number, "kind" => kind, "signer_name" => signer_name, "email" => email,
      "message" => message, "at" => created_at.utc.iso8601(6), "ip_address" => ip_address, "user_agent" => user_agent,
      "device" => device, "client_link_id" => client_link_id, "recorded_by_id" => recorded_by_id,
      "quote_version" => quote_version, "snapshot_digest" => snapshot_digest
    }
    key = Rails.application.key_generator.generate_key("quote_response_signature", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, JSON.generate(self.class.canonical(evidence)))
  end

  def capture_snapshot
    self.snapshot = self.class.snapshot_of(quote)
    self.snapshot_digest = self.class.digest(snapshot)
  end
end
