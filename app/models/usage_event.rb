# A billable event (QTE-04 records "quote_sent"; BIL-02 counts them per business per period).
# Recorded at most once per kind and subject, even under retries and concurrent requests.
class UsageEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[quote_sent].freeze

  belongs_to :subject, polymorphic: true

  validates :kind, inclusion: { in: KINDS }

  # True when this call recorded it; false when it was already there.
  def self.record!(kind, subject, at: Time.current)
    raise ArgumentError, "unknown usage kind #{kind}" unless KINDS.include?(kind)

    result = insert({ business_id: subject.business_id, kind:, subject_type: subject.class.polymorphic_name, subject_id: subject.id,
                      occurred_at: at, created_at: at, updated_at: at },
                    unique_by: %i[kind subject_type subject_id])
    result.rows.any?
  end
end
