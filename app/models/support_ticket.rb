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

  private

  def status_changes(status)
    status = STATUSES.key?(status) ? status : self.status
    { status:, waiting_since: (status == "waiting" ? Time.current : nil), resolved_at: (status == "resolved" ? Time.current : nil) }
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
