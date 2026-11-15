# Sequential, per-business document numbers: Q-0001, Q-0002 … and INV-0001 …
#
#   business.next_document_number(:quote)   # => "Q-0001"
#
# One atomic upsert per number, so concurrent requests never get the same number, and a number
# is never handed out twice even if its document is later deleted (gaps are allowed, reuse is
# not). Call it inside the transaction that creates the document so a rollback doesn't burn
# a number needlessly; a burnt number only leaves a gap.
module DocumentNumber
  PREFIXES = { quote: "Q", invoice: "INV", job: "J" }.freeze
  MIN_DIGITS = 4

  class UnknownKind < ArgumentError; end

  def self.next!(business, kind)
    format(kind, next_value!(business, kind), prefix: business_prefix(business, kind))
  end

  def self.format(kind, value, prefix: prefix(kind))
    "#{prefix}-#{value.to_s.rjust(MIN_DIGITS, "0")}"
  end

  # Businesses can choose their quote and invoice prefixes (CAT-01).
  def self.business_prefix(business, kind)
    case kind.to_sym
    when :quote then business.quote_number_prefix.presence
    when :invoice then business.invoice_number_prefix.presence
    end || prefix(kind)
  end

  def self.prefix(kind)
    PREFIXES.fetch(kind.to_sym) { raise UnknownKind, "No document numbering for #{kind.inspect}" }
  end

  def self.next_value!(business, kind)
    prefix(kind)
    sql = <<~SQL.squish
      INSERT INTO document_sequences (business_id, kind, last_value, created_at, updated_at)
      VALUES ($1, $2, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (business_id, kind)
      DO UPDATE SET last_value = document_sequences.last_value + 1, updated_at = CURRENT_TIMESTAMP
      RETURNING last_value
    SQL
    ActiveRecord::Base.connection.exec_query(sql, "DocumentNumber", [ business.id, kind.to_s ]).rows.first.first
  end
end
