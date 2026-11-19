# OPS-05: a business asking Shadetree for help (never a business's own clients asking the
# business; ADR 0020). Any member opens one from the Help menu, with the page and browser it came
# from; members follow it in the app and by email, operators answer from the console's inbox.
#
#   ticket = SupportTicket.open!(opened_by: user, subject:, category:, body:, files:, page:, browser:)
#   ticket.reply_from_member!(user, body)        # reopens a resolved ticket
#   ticket.reply_from_operator!(operator, body)  # "Waiting on you" unless another status is chosen
class SupportTicket < ApplicationRecord
  include BusinessOwned

  CATEGORIES = { "question" => "Question", "bug" => "Something isn't working", "billing" => "Billing", "feature" => "Feature request" }.freeze
  STATUSES = { "open" => "Open", "waiting" => "Waiting on you", "resolved" => "Resolved" }.freeze

  belongs_to :opened_by, class_name: "User", optional: true
  belongs_to :assignee, class_name: "User", optional: true
  has_many :messages, -> { order(:created_at, :id) }, class_name: "SupportMessage", inverse_of: :support_ticket, dependent: :destroy

  normalizes :subject, with: ->(subject) { subject.to_s.squish }
  validates :subject, presence: true, length: { maximum: 150 }
  validates :category, inclusion: { in: CATEGORIES.keys, message: "pick one" }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :page, length: { maximum: 500 }

  scope :recent, -> { order(last_message_at: :desc, id: :desc) }
  scope :unresolved, -> { where.not(status: "resolved") }

  # "Waiting on you" tickets with no answer after this long are resolved, with a notice.
  # A whole number of days from SUPPORT_AUTO_RESOLVE_DAYS; anything else means 7, never a failed boot.
  def self.auto_resolve_days(value) = Integer(value.to_s, 10, exception: false)&.then { _1.positive? ? _1 : nil } || 7
  AUTO_RESOLVE_AFTER = auto_resolve_days(ENV.fetch("SUPPORT_AUTO_RESOLVE_DAYS", "7")).days
  AUTO_RESOLVE_NOTICE = "We've marked this resolved because we haven't heard back. Reply any time to reopen it.".freeze

  # Run daily (ResolveStaleSupportTicketsJob). Returns how many were resolved.
  # Each ticket on its own: one that fails is reported and the rest go on.
  def self.resolve_stale!(before: AUTO_RESOLVE_AFTER.ago)
    reason = "resolving stale support tickets (OPS-05)"
    ids = Tenancy.across_businesses(reason:) { where(status: "waiting", waiting_since: ...before).pluck(:id) }
    ids.count do |id|
      ticket = Tenancy.across_businesses(reason:) { includes(:business).find_by(id:) }
      ticket && Tenancy.with_business(ticket.business) { ticket.resolve_if_still_unanswered!(before) }
    rescue StandardError => error
      Rails.error.report(error, context: { support_ticket_id: id })
      false
    end
  end

  # Resolves it, with the notice and the audit entry, only if it's still been waiting since
  # before `before` once locked: a reply or a status change in the meantime wins.
  def resolve_if_still_unanswered!(before)
    message = with_lock do
      next unless status == "waiting" && waiting_since && waiting_since < before

      resolve_unanswered!.tap do
        AuditEntry.record!(operator: nil, operator_email: "system", action: "ticket.auto_resolved", business:, user: opened_by, ticket: uid)
      end
    end
    message && SupportNotifier.replied(self, message, title: "Resolved: #{subject}")
    message.present?
  end

  def self.open!(opened_by:, body:, files: [], **attributes)
    ticket = new(opened_by:, status: "open", last_message_at: Time.current, **attributes)
    message = ticket.messages.build(author: opened_by, body:)
    message.attach_files(files)
    transaction { ticket.save! } if ticket.valid? & message.valid?
    ticket.errors.merge!(message.errors) unless ticket.persisted?
    ticket
  end

  def status_label = STATUSES.fetch(status)
  def category_label = CATEGORIES.fetch(category)
  def reference = "##{uid}"

  # What the business sees: everything but operators' internal notes.
  def visible_messages = messages.reject(&:internal?)

  # A member's reply reopens the ticket.
  def reply_from_member!(user, body, files: [], source: "app")
    add_message!(author: user, body:, files:, source:) do
      { status: "open", waiting_since: nil, resolved_at: nil }
    end
  end

  def reply_from_operator!(operator, body, status: "waiting")
    add_message!(author: operator, body:, from_operator: true) { status_changes(status) }
  end

  def note!(operator, body) = add_message!(author: operator, body:, from_operator: true, internal: true, touch: false) { {} }

  def change_status!(status) = update!(status_changes(status))

  # Resolved with a notice in the thread, after the member didn't answer.
  def resolve_unanswered! = add_message!(body: AUTO_RESOLVE_NOTICE, from_operator: true, source: "system") { status_changes("resolved") }

  private

  def status_changes(status)
    status = STATUSES.key?(status) ? status : self.status
    # The clocks start when a status is entered; setting the same status again doesn't restart them.
    { status:, waiting_since: (status == "waiting" ? (self.status == "waiting" && waiting_since) || Time.current : nil),
      resolved_at: (status == "resolved" ? (self.status == "resolved" && resolved_at) || Time.current : nil) }
  end

  # Returns the saved message, or one with errors.
  def add_message!(touch: true, files: [], **attributes)
    message = SupportMessage.new(support_ticket: self, **attributes)
    message.attach_files(files)
    return message unless message.valid?

    transaction do
      message.save!
      update!(yield.merge(touch ? { last_message_at: message.created_at } : {}))
    end
    message
  end
end
