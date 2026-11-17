# Every email the product sends, in one place (08-notifications R10). A message type is
# added here before any code sends it; EmailMessage#kind must be one of these keys, and the
# development previews (/rails/mailers) cover each one that exists.
module EmailCatalog
  Entry = Data.define(:kind, :name, :recipient, :trigger, :spec, :client_facing)

  ENTRIES = [
    # kind, name, recipient, trigger, owning spec, client-facing?
    [ "test_message", "Test email", "Owner/Admin", "Send me a test email (branding settings)", "NTF-01", true ],
    [ "request_received", "Request received", "Client", "A client submits the request form", "CLI-03", true ],
    [ "new_request", "New request", "Team", "A client submits the request form", "CLI-03", false ],
    [ "quote_sent", "Quote sent", "Client", "Staff send a quote", "QTE-04", true ],
    [ "quote_approved", "Quote approved", "Client", "A client approves a quote", "QTE-05", true ],
    [ "quote_activity", "Quote viewed / approved / declined / changes requested", "Team", "A client acts on a quote", "QTE-05", false ],
    [ "visit_scheduled", "Visit scheduled / changed / cancelled / reminder", "Client", "A visit is booked, moved, cancelled or due", "JOB-05", true ],
    [ "visit_assigned", "Visit assigned / changed", "Technician", "A visit is assigned or changed", "JOB-02", false ],
    [ "invoice_sent", "Invoice sent", "Client", "Staff send an invoice", "PAY-02", true ],
    [ "payment_receipt", "Payment receipt", "Client", "A payment succeeds", "PAY-04", true ],
    [ "invoice_paid", "Invoice paid", "Team", "An invoice is paid", "PAY-04, PAY-05", false ],
    [ "team_invitation", "Team invitation", "Invitee", "An owner or admin invites someone", "ACC-03", false ]
  ].map { Entry.new(*_1) }.freeze

  def self.all = ENTRIES
  def self.kinds = ENTRIES.map(&:kind)
  def self.find(kind) = ENTRIES.find { _1.kind == kind.to_s } || raise(ArgumentError, "No email type #{kind.inspect} in EmailCatalog")
end
