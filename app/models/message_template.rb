# NTF-03: a business's own wording for a client-facing email. Each editable message in
# EmailCatalog has a default (DEFINITIONS) that matches what the product sends; saving one
# makes it "customized", and deleting it goes back to the default. Only the subject and the
# opening text are editable: the branded layout, the summary, the button to the client's page
# and the footer stay fixed, so a template can't hide the link or the business's details.
#
# Text is plain: placeholders like {{client_first_name}} are filled in when the email is built,
# and everything is escaped, so markup shows as typed (and is refused when saving).
#
#   template = MessageTemplate.for_kind("quote_sent")      # nil: the default is used
#   MessageTemplate.render("Hi {{client_first_name}}", { "client_first_name" => "Maria" })
class MessageTemplate < ApplicationRecord
  include BusinessOwned

  Definition = Data.define(:kind, :subject, :body, :placeholders, :hint)

  # Every placeholder, with what it's filled with (shown beside the editor).
  PLACEHOLDERS = {
    "client_first_name" => "The client's first name",
    "client_name" => "The client's full name",
    "business_name" => "Your business name",
    "your_name" => "Your first name (whoever sends it)",
    "quote_number" => "The quote number, like Q-1041",
    "quote_title" => "The quote's title",
    "invoice_number" => "The invoice number, like INV-2210",
    "invoice_title" => "The invoice's title",
    "total" => "The total, like $1,250.00",
    "balance" => "What's left to pay",
    "valid_until" => "The quote's valid-until date",
    "due_date" => "The invoice's due date",
    "visit_window" => "The visit's day and time, like Tue, Nov 17 · 8–10 AM",
    "signer_name" => "The name the client signed with",
    "next_steps" => "Your “what happens next” text (Settings → Documents)",
    "link" => "The link to the client's page (the button is always there too)"
  }.freeze

  # The editable messages and their defaults: the same words the product sends without a
  # template. For quote and invoice emails the body is the note the send form starts with.
  DEFINITIONS = [
    Definition.new("request_received", "{{business_name}} received your request",
                   "Thanks for your request\n\n{{business_name}} has it and will be in touch soon.",
                   %w[client_first_name client_name business_name], "When a client sends your request form."),
    Definition.new("quote_sent", "Quote {{quote_number}} from {{business_name}}: {{quote_title}}",
                   "Hi {{client_first_name}},\n\nThanks for the chance to quote this work. You can see all the details with the button below. " \
                   "The PDF is attached too.\n\nAny questions, just reply to this email.\n\n{{your_name}}",
                   %w[client_first_name client_name business_name your_name quote_number quote_title total valid_until],
                   "Fills the send form; you can still change it for each quote."),
    Definition.new("quote_approved", "You approved quote {{quote_number}} from {{business_name}}",
                   "Thanks, {{signer_name}}. You're all set.\n\n{{next_steps}}",
                   %w[client_first_name client_name signer_name business_name quote_number quote_title total next_steps link],
                   "When a client approves a quote. The approved PDF is attached."),
    Definition.new("visit_scheduled", "Visit booked: {{visit_window}}",
                   "Hi {{client_name}},\n\nYour visit is booked. We'll see you then.",
                   %w[client_first_name client_name business_name visit_window], "When you book one visit. Booking several at once sends the standard wording."),
    Definition.new("visit_changed", "Visit moved to {{visit_window}}",
                   "Hi {{client_name}},\n\nYour visit has moved. Here's when we'll be there now.",
                   %w[client_first_name client_name business_name visit_window], "When you move one visit. Several changes at once send the standard wording."),
    Definition.new("visit_cancelled", "Visit cancelled: {{visit_window}}",
                   "Hi {{client_name}},\n\nYour visit is cancelled. Get in touch if you'd like to book another time.",
                   %w[client_first_name client_name business_name visit_window], "When you cancel one visit. Several at once send the standard wording."),
    Definition.new("visit_reminder", "Reminder: your visit tomorrow, {{visit_window}}",
                   "Hi {{client_name}},\n\nA reminder that {{business_name}} is coming tomorrow.",
                   %w[client_first_name client_name business_name visit_window], "The day before a visit."),
    Definition.new("invoice_sent", "Invoice {{invoice_number}} from {{business_name}}: {{invoice_title}}",
                   "Hi {{client_first_name}},\n\nThanks for your business. Your invoice is ready: you can see the details with the button below, " \
                   "and the PDF is attached.\n\nAny questions, just reply to this email.\n\n{{your_name}}",
                   %w[client_first_name client_name business_name your_name invoice_number invoice_title total balance due_date],
                   "Fills the send form; you can still change it for each invoice. Sending a revised invoice uses the standard note."),
    Definition.new("payment_receipt", "Receipt for invoice {{invoice_number}} from {{business_name}}",
                   "Thank you. We've received your payment.",
                   %w[client_first_name client_name business_name invoice_number invoice_title balance link], "When a payment is recorded and you choose to send a receipt.")
  ].index_by(&:kind).freeze

  # Filled in for the preview, and for checking a template renders.
  SAMPLE = {
    "client_first_name" => "Maria", "client_name" => "Maria Lopez", "your_name" => "Dana",
    "quote_number" => "Q-1041", "quote_title" => "Spring cleanup", "invoice_number" => "INV-2210", "invoice_title" => "Spring cleanup",
    "total" => "$1,250.00", "balance" => "$450.00", "valid_until" => "Dec 19, 2026", "due_date" => "Dec 3, 2026",
    "visit_window" => "Tue, Nov 17 · 8–10 AM", "signer_name" => "Maria Lopez", "link" => "https://getshadetree.com/c/…"
  }.freeze

  PLACEHOLDER = /\{\{\s*([a-z_]+)\s*\}\}/
  MARKUP = %r{<\s*(?:/?\s*[a-z][a-z0-9-]*[\s/>]|[!?])}i # tag-like: "<b>", "</p>", "<img ", "<!--"; not "call you <soon"

  belongs_to :updated_by, class_name: "User", optional: true

  normalizes :subject, with: ->(text) { text.to_s.squish }
  normalizes :body, with: ->(text) { text.to_s.gsub("\r\n", "\n").strip }

  validates :kind, inclusion: { in: DEFINITIONS.keys }, uniqueness: { scope: :business_id }
  validates :subject, presence: true, length: { maximum: 200 }
  validates :body, presence: true, length: { maximum: 5_000 }
  validate :known_placeholders, :no_markup

  def self.definition(kind) = DEFINITIONS.fetch(kind.to_s)
  def self.for_kind(kind) = find_by(kind: kind.to_s)

  # Placeholders filled in; an unknown or empty one becomes nothing.
  def self.render(text, values) = text.to_s.gsub(PLACEHOLDER) { values[Regexp.last_match(1)].to_s }

  # A subject is one line, and loses the separator an empty placeholder left at its end
  # ("Quote Q-1 from Oakline: " when the quote has no title).
  def self.render_subject(text, values) = render(text, values).squish.sub(/[\s:·–-]+\z/, "")

  def definition = self.class.definition(kind)
  def placeholders = definition.placeholders

  # What it would say with sample values (and the business's real name and next steps).
  def preview(business)
    values = SAMPLE.merge("business_name" => business.name, "next_steps" => business.quote_next_steps)
    [ self.class.render_subject(subject, values), self.class.render(body, values) ]
  end

  private

  def known_placeholders
    return unless DEFINITIONS.key?(kind)

    unknown = (subject.to_s.scan(PLACEHOLDER) + body.to_s.scan(PLACEHOLDER)).flatten.uniq - placeholders
    errors.add(:base, "#{unknown.map { "{{#{_1}}}" }.to_sentence} #{unknown.one? ? "isn't a placeholder" : "aren't placeholders"} for this message.") if unknown.any?
  end

  def no_markup
    errors.add(:base, "Write plain text: HTML and code can't be used in an email template.") if [ subject, body ].any? { _1.to_s.match?(MARKUP) }
  end
end
