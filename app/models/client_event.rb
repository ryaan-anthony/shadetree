# One line of a client's timeline (CLI-05), recorded by the feature it belongs to at the time
# it happens, in the same transaction:
#
#   ClientEvent.record!(quote.client, :quote_sent, subject: quote, by: user, channel: "email")
#
# The subject is the record it's about (a quote, visit, invoice, payment, request or note);
# data holds what the line says that the subject may not keep (a channel, an amount).
class ClientEvent < ApplicationRecord
  include BusinessOwned

  KINDS = %w[request_received quote_sent quote_viewed quote_approved quote_declined quote_changes_requested
             visit_scheduled visit_completed invoice_sent invoice_viewed invoice_paid payment_recorded
             email_bounced note_added].freeze
  PAGE_SIZE = 25

  belongs_to_business_record :client
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }

  # Newest first, a page at a time: `before` is the last event of the previous page.
  scope :timeline, -> { order(occurred_at: :desc, id: :desc) }

  def self.record!(client, kind, subject: nil, by: nil, at: Time.current, **data)
    return unless client

    create!(business: client.business, client:, kind: kind.to_s, subject:, user: by, data:, occurred_at: at)
  end

  # A page of a client's events, newest first, after `before` (the last one shown), and
  # whether there are more.
  def self.page_for(client, before: nil)
    scope = client.events.timeline.includes(:user, :subject)
    scope = scope.where("(client_events.occurred_at, client_events.id) < (?, ?)", before.occurred_at, before.id) if before
    events = scope.limit(PAGE_SIZE + 1).to_a
    subjects = events.filter_map(&:subject)
    ActiveRecord::Associations::Preloader.new(records: subjects.grep(Visit), associations: :job).call
    ActiveRecord::Associations::Preloader.new(records: subjects.grep(Payment), associations: :invoice).call
    [ events.first(PAGE_SIZE), events.size > PAGE_SIZE ]
  end
end
