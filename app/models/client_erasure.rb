# INS-02: honoring a client's request to be forgotten. Their personal data goes, wherever the
# business typed or Shadetree wrote it, while quotes, jobs, invoices and payments stay with
# their numbers, line items and totals under "Erased client":
#
# - removed: contacts, notes (theirs, and the messages, instructions and internal notes on their
#   documents, jobs and visits), timeline, request details and photos, document and visit photos
#   and files, approval signatures, the addresses documents were sent to, stored PDFs (current
#   and every revision's), client-link activity;
# - scrubbed (their name, company, emails, phones and address replaced with "[erased]"): titles,
#   line items, terms, revision and approval snapshots,
#   document and visit histories, payment notes and references, notifications about them, email
#   subjects, and other clients' notes that mention them by full name, email, phone or address;
# - closed: open requests are archived and visits not yet done are cancelled (nobody is told),
#   and every client link stops working.
#
# The client's quotes and invoices are locked meanwhile. Afterwards nothing can be sent to the
# client, answered or linked again (`client.erased?` checks in Quote, Invoice and ClientLink).
# Files are deleted once the change commits. Full exports that may hold the details are
# removed, and the erasure is logged (who, when) in the business's data log.
#
# Kept: email suppressions (a bounced or complained address stays blocked, so a re-added
# client isn't mailed against their wishes — a legitimate interest the privacy notice states).
#
#   ClientErasure.new(client, by: current_user).erase!
class ClientErasure
  NAME = "Erased client"
  ADDRESS = "Erased address"
  REDACTED = "[erased]"
  ERASED_EMAIL = "erased@erased.invalid"
  VISIT_CANCEL_REASON = "Client's details erased"

  def initialize(client, by:)
    @client = client
    @by = by
    @blob_ids = []
  end

  def erase!
    ActiveRecord::Base.transaction do
      @client.lock!
      return false if @client.erased?

      @quotes = @client.quotes.order(:id).lock.to_a
      @invoices = @client.invoices.order(:id).lock.to_a
      @strong, @all = identifiers
      erase_documents
      erase_jobs_and_visits
      erase_requests
      erase_mentions
      erase_contact
      DataExport.where(kind: "full", status: "ready").find_each(&:expire!)
      DataExport.create!(kind: "client_erased", requested_by: @by, requested_by_email: @by.email)
    end
    blob_ids = @blob_ids.compact.uniq
    # Once committed (an outer transaction included): a rollback mustn't leave records pointing at deleted files.
    ActiveRecord.after_all_transactions_commit { ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge_later) } if blob_ids.any?
    true
  end

  private

  # [strong, all], each [words, phone digits]. Strong identifiers (full name, company, emails,
  # phones, address lines) are also scrubbed from other clients' notes; all adds the first and
  # last name on their own, for text on this client's own records ("Hi Priya").
  def identifiers
    emails = @client.contact_methods.select(&:email?).map(&:value)
    strong = [ @client.display_name, @client.company_name, *emails ] + @client.properties.flat_map { [ _1.address_line1, _1.address_line2 ] }
    strong = strong.compact_blank.map(&:strip).select { _1.length >= 3 }.uniq
    name_parts = @client.display_name.to_s.split.select { _1.length >= 3 && _1.match?(/\A\p{L}/) }
    # With a country code, the national number on its own too ("+1 555…" written as "555…").
    phones = @client.contact_methods.select(&:phone?).map { _1.value.gsub(/\D/, "") }.select { _1.length >= 7 }
    phones = phones.flat_map { _1.length > 10 ? [ _1, _1[-10..] ] : [ _1 ] }.uniq.sort_by { -_1.length }
    [ [ strong, phones ], [ (strong + name_parts).uniq, phones ] ]
  end

  # The text with identifiers replaced, as whole words, any case; phone numbers match however
  # they're punctuated ("(555) 010-2030", "555.010.2030", "+1 555 010 2030").
  def scrub(text, set = @all)
    return text unless text.is_a?(String) && text.present?

    words, phones = set
    out = words.sort_by { -_1.length }.reduce(text) do |acc, word|
      acc.gsub(/(?<![\p{L}\p{N}])#{Regexp.escape(word)}(?![\p{L}\p{N}])/i, REDACTED)
    end
    phones.reduce(out) do |acc, digits|
      acc.gsub(/(?<!\d)(?:\+\d{1,3}[\s.-]*)?\(?#{digits.chars.map { Regexp.escape(_1) }.join('[\s().+\-]*')}(?!\d)/, REDACTED)
    end
  end

  # Snapshots and histories: the client and property blocks are emptied, any other text scrubbed.
  def scrub_data(data, set = @all)
    case data
    when Hash then data.to_h { |key, value| [ key, %w[client property recipient cc email].include?(key.to_s) ? blank_like(value) : scrub_data(value, set) ] }
    when Array then data.map { scrub_data(_1, set) }
    when String then scrub(data, set)
    else data
    end
  end

  def blank_like(value) = value.is_a?(Hash) ? {} : nil

  # Some of these are read-only through the app (histories, approvals), so this writes directly.
  def scrub_columns(record, *columns, set: @all)
    changes = columns.to_h { [ _1, scrub(record.public_send(_1), set) ] }.reject { |column, value| value == record.public_send(column) }
    record.class.where(id: record.id).update_all(changes) if changes.any?
  end

  def scrub_events(events) = events.each { _1.class.where(id: _1.id).update_all(data: scrub_data(_1.data)) }

  def drop_files(attachments)
    @blob_ids.concat(attachments.map(&:blob_id))
    attachments.delete_all
  end

  def stop_links(linkable)
    links = ClientLink.where(linkable:)
    ClientLinkEvent.where(client_link_id: links.select(:id)).delete_all
    links.where(revoked_at: nil).update_all(revoked_at: Time.current, revoked_by_id: @by.id)
  end

  def erase_documents
    (@quotes + @invoices).each do |document|
      drop_files(document.attachments_attachments)
      @blob_ids << document.pdf_blob_id
      scrub_columns(document, :title, :terms)
      document.class.where(id: document.id).update_all(message: nil, internal_notes: nil, pdf_blob_id: nil, pdf_digest: nil)
      document.line_items.each { scrub_columns(_1, :name, :description) }
      document.revisions.each do |revision|
        @blob_ids << revision.pdf_blob_id
        revision.class.where(id: revision.id).update_all(snapshot: scrub_data(revision.snapshot), pdf_blob_id: nil)
      end
      document.sends.update_all(recipient: nil, cc: nil)
      scrub_events(document.events)
      stop_links(document)
    end
    @invoices.each { |invoice| invoice.payments.each { scrub_columns(_1, :note, :reference) } }
    @quotes.each { |quote| quote.responses.each { erase_response(_1) } }
  end

  # The approval keeps what was agreed (lines and totals in its snapshot) but not who signed or
  # from where. It's signed again as it now is, so it still verifies.
  def erase_response(response)
    snapshot = scrub_data(response.snapshot)
    response.assign_attributes(signer_name: NAME, email: nil, message: nil, ip_address: nil, user_agent: nil, device: nil, snapshot:,
                               snapshot_digest: snapshot.present? ? QuoteResponse.digest(snapshot) : response.snapshot_digest)
    response.signature = response.send(:compute_signature)
    QuoteResponse.where(id: response.id).update_all(response.changes.transform_values(&:last))
  end

  def erase_jobs_and_visits
    @client.jobs.find_each do |job|
      drop_files(job.attachments_attachments)
      scrub_columns(job, :title, :cancel_reason)
      Job.where(id: job.id).update_all(instructions: nil, internal_notes: nil)
      job.line_items.each { scrub_columns(_1, :name, :description) }
    end
    Visit.joins(:job).where(jobs: { client_id: @client.id }).find_each do |visit|
      drop_files(visit.photos_attachments)
      visit.notes.delete_all
      scrub_events(visit.events)
      stop_links(visit)
      changes = { instructions: nil, client_note: nil }
      changes.merge!(status: "cancelled", cancelled_at: Time.current, cancel_reason: VISIT_CANCEL_REASON) if visit.open?
      Visit.where(id: visit.id).update_all(changes) # not through the model: nobody is told
    end
  end

  def erase_requests
    @client.service_requests.find_each do |request|
      drop_files(request.photos_attachments)
      request.notes.delete_all
      changes = { contact_name: nil, contact_email: nil, contact_phone: nil, description: nil, address: {} }
      changes[:status] = "archived" unless request.status == "quoted"
      ServiceRequest.where(id: request.id).update_all(changes)
    end
  end

  # Notifications and emails about them, and other clients' notes that mention them.
  def erase_mentions
    subjects = { "Quote" => @quotes.map(&:id), "Invoice" => @invoices.map(&:id), "Job" => @client.jobs.ids,
                 "Visit" => Visit.joins(:job).where(jobs: { client_id: @client.id }).ids,
                 "ServiceRequest" => @client.service_requests.ids, "Client" => [ @client.id ] }
    subjects.each do |type, ids|
      next if ids.empty?

      Notification.where(subject_type: type, subject_id: ids).find_each { scrub_columns(_1, :title, :body) }
      EmailMessage.where(related_type: type, related_id: ids).find_each do |message|
        EmailMessage.where(id: message.id).update_all(to: ERASED_EMAIL, subject: scrub(message.subject))
      end
    end
    emails = @client.contact_methods.select(&:email?).map { _1.value.downcase }
    EmailMessage.where("lower(email_messages.to) IN (?)", emails).update_all(to: ERASED_EMAIL) if emails.any?
    Client.where.not(id: @client.id).where.not(notes: [ nil, "" ]).find_each { scrub_columns(_1, :notes, set: @strong) }
    ClientNote.where.not(client_id: @client.id).find_each { scrub_columns(_1, :body, set: @strong) }
  end

  def erase_contact
    @client.properties.update_all(label: nil, address_line1: ADDRESS, address_line2: nil, city: nil, region: nil, postal_code: nil, access_notes: nil)
    @client.contact_methods.delete_all
    @client.events.delete_all
    @client.timeline_notes.delete_all
    @client.update_columns(display_name: NAME, company_name: nil, notes: nil, tags: [], search_text: "",
                           archived_at: @client.archived_at || Time.current, erased_at: Time.current, updated_at: Time.current)
  end
end
