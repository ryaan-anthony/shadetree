# A quote for a client (QTE-01). Drafts are built and autosaved in the builder; sending,
# the client page, approval and revisions come with QTE-02..QTE-06.
#
# Everything a client will see is copied onto the quote when it's made (line items from the
# catalog, tax rates, terms, currency), so later catalog, tax or settings changes never
# alter it. Totals always come from Pricing::DocumentTotals (PLT-08); the *_cents total
# columns are a cache for lists, refreshed on every save.
class Quote < ApplicationRecord
  include BusinessOwned
  include HasMoney
  include HasDiscount

  STATUSES = %w[draft].freeze # QTE-04+ add sent, viewed, approved, declined, changes_requested, expired
  MAX_LINES = 200
  MAX_ATTACHMENTS = 10
  ATTACHMENT_MAX_BYTES = 10.megabytes
  ATTACHMENT_TYPES = %w[image/png image/jpeg image/webp application/pdf].freeze

  belongs_to_business_record :client
  belongs_to_business_record :property, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :line_items, -> { order(:position, :id) }, class_name: "QuoteLineItem", inverse_of: :quote,
           dependent: :delete_all, autosave: true
  has_many_attached :attachments

  def discount_currency = currency

  normalizes :title, with: ->(value) { value.to_s.squish.presence }
  normalizes :message, :internal_notes, :terms, with: ->(value) { value.to_s.strip.presence }

  validates :number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :title, length: { maximum: 120 }
  validates :message, :terms, length: { maximum: 5_000 }
  validates :internal_notes, length: { maximum: 5_000 }
  validate :property_belongs_to_client
  validate :tax_rates_are_valid
  validate :not_too_many_lines
  validate :attachments_are_allowed

  before_validation :assign_number_and_defaults, on: :create
  before_save :cache_totals

  scope :drafts, -> { where(status: "draft") }

  def draft? = status == "draft"
  def editable? = draft?

  # Starts a draft for a client with the business's defaults: next number, expiry, terms,
  # and the tax rates new documents get (none for a tax-exempt client).
  def self.start(client:, property: nil, created_by: nil)
    create!(client:, property: property || client.billing_property || client.properties.first, created_by:)
  end

  def tax_rate_list = tax_rates.map { Pricing::TaxRate.new(name: _1["name"], percent: _1["percent"]) }

  # Replaces the quote's tax rates with these (name/percent pairs or Pricing::TaxRate).
  def tax_rate_list=(rates)
    self.tax_rates = Array(rates).map { |rate| { "name" => rate.name.to_s, "percent" => rate.percent.to_d.to_s("F") } }.uniq
  end

  def totals
    Pricing::DocumentTotals.new(
      currency:, discount: pricing_discount, prices_include_tax:,
      lines: current_line_items.map { _1.to_pricing(tax_rate_list) }
    )
  end

  # Lines as the builder sees them: in order, without ones being removed.
  def current_line_items = line_items.reject(&:marked_for_destruction?).sort_by(&:position)

  def subtotal = Money.new(subtotal_cents, currency)
  def total = Money.new(total_cents, currency)

  # Attaches uploaded files: photos are checked and re-encoded without their metadata (phone
  # photos carry GPS), PDFs are kept as they are if they really are PDFs. Problems are added
  # as errors on save.
  def attach_files(files)
    @attachment_errors = []
    Array(files).compact_blank.each do |file|
      name = file.respond_to?(:original_filename) ? file.original_filename : "file"
      if pdf?(file)
        next @attachment_errors << "#{name} must be smaller than #{ATTACHMENT_MAX_BYTES / 1.megabyte} MB" if file.size > ATTACHMENT_MAX_BYTES

        attachments.attach(file)
      else
        result = LogoUpload.clean_photo(file, max_bytes: ATTACHMENT_MAX_BYTES)
        next @attachment_errors << "#{name} #{result.error.sub("must be a PNG, JPEG or WebP image", "must be a photo (PNG, JPEG, WebP) or a PDF")}" if result.error

        attachments.attach(result.attachable)
      end
    end
  end

  # A real PDF starts with "%PDF-"; the name or claimed type doesn't count. (PDFs are kept as
  # uploaded, metadata included; only photos are re-encoded.)
  def pdf?(file)
    io = file.respond_to?(:tempfile) ? file.tempfile : file
    header = io.read(5).tap { io.rewind }
    header == "%PDF-"
  end

  # Makes the saved lines match `rows` (the builder's full list, in order): rows are matched
  # by their browser-made key, so autosaving again updates instead of duplicating, and
  # saved lines missing from `rows` are removed. Call inside a transaction with save.
  def sync_line_items(rows)
    rows = Array(rows).first(MAX_LINES + 1)
    by_key = line_items.index_by(&:key)
    kept = rows.each_with_index.map do |row, index|
      row = row.to_h.stringify_keys
      item = by_key[row["key"].to_s] || line_items.build(key: row["key"].presence || SecureRandom.uuid)
      item.assign_row(row, position: index)
      item
    end
    (line_items.to_a - kept).each(&:mark_for_destruction)
    @row_count = rows.size
    kept
  end

  private

  def assign_number_and_defaults
    return unless business

    self.number ||= business.next_document_number(:quote)
    self.currency ||= business.currency_code
    self.expires_on ||= business.today + business.quote_expiry_days.to_i.days if business.quote_expiry_days.to_i.positive?
    self.terms ||= business.quote_terms
    self.tax_rate_list = TaxRate.for_new_document(client:) if tax_rates.blank?
  end

  def cache_totals
    result = totals
    self.subtotal_cents = result.subtotal.cents
    self.discount_total_cents = (result.discount + Money.sum(result.lines.map(&:discount), currency)).cents
    self.tax_cents = result.tax_total.cents
    self.total_cents = result.total.cents
  end

  def property_belongs_to_client
    errors.add(:property, "must be one of this client's properties") if property && client && property.client_id != client.id
  end

  def tax_rates_are_valid
    return errors.add(:tax_rates, "must be a list") unless tax_rates.is_a?(Array)

    tax_rate_list
  rescue ArgumentError, TypeError
    errors.add(:tax_rates, "must each have a name and a percent from 0 to 100")
  end

  def not_too_many_lines
    errors.add(:base, "A quote can have at most #{MAX_LINES} lines.") if (@row_count || line_items.size) > MAX_LINES
  end

  def attachments_are_allowed
    Array(@attachment_errors).each { errors.add(:base, _1) }
    errors.add(:base, "A quote can have at most #{MAX_ATTACHMENTS} files.") if attachments.size > MAX_ATTACHMENTS
  end
end
