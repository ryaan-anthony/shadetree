# INS-02: honoring a client's request to be forgotten. Their personal data goes — name, contacts,
# addresses, notes, timeline, request details and photos, visit photos, signatures and the
# addresses their emails went to — while quotes, jobs, invoices and payments stay with their
# numbers and totals under "Erased client". Stored PDFs are removed (they'd be made again
# without the details), client links stop working, and full exports that may hold the details
# are removed. Logged (who, when) in the business's data log.
#
#   ClientErasure.new(client, by: current_user).erase!
class ClientErasure
  NAME = "Erased client"
  ADDRESS = "Erased address"
  REDACTED = "[erased]"

  def initialize(client, by:)
    @client = client
    @by = by
  end

  def erase!
    ActiveRecord::Base.transaction do
      @client.lock!
      return false if @client.erased?

      identifiers = personal_strings
      erase_documents(identifiers)
      erase_requests
      erase_visits
      erase_properties
      emails = @client.contact_methods.select(&:email?).map { _1.value.downcase }
      EmailMessage.where("lower(email_messages.to) IN (?)", emails).update_all(to: "erased@erased.invalid") if emails.any?
      @client.contact_methods.delete_all
      @client.events.delete_all
      @client.timeline_notes.delete_all
      @client.update_columns(display_name: NAME, company_name: nil, notes: nil, tags: [], search_text: "",
                             archived_at: @client.archived_at || Time.current, erased_at: Time.current, updated_at: Time.current)
      DataExport.where(kind: "full", status: "ready").find_each(&:expire!)
      DataExport.create!(kind: "client_erased", requested_by: @by, requested_by_email: @by.email)
    end
    true
  end

  private

  # Everything that names or reaches the person, longest first, for scrubbing free text and logs.
  def personal_strings
    values = [ @client.display_name, @client.company_name, *@client.contact_methods.map(&:value) ]
    values += @client.properties.flat_map { [ _1.address_line1, _1.address_line2 ] }
    values.compact_blank.select { _1.length >= 3 }.uniq.sort_by { -_1.length }
  end

  def scrub(text, identifiers) = identifiers.reduce(text.to_s) { |out, value| out.gsub(value, REDACTED) }

  def scrub_data(data, identifiers)
    case data
    when Hash then data.transform_values { scrub_data(_1, identifiers) }
    when Array then data.map { scrub_data(_1, identifiers) }
    when String then scrub(data, identifiers)
    else data
    end
  end

  def erase_documents(identifiers)
    [ @client.quotes, @client.invoices ].each do |documents|
      documents.find_each do |document|
        document.attachments.purge
        document.update_columns(message: nil, internal_notes: nil, pdf_blob_id: nil, pdf_digest: nil)
        document.events.find_each { _1.update_columns(data: scrub_data(_1.data, identifiers)) }
        ClientLink.where(linkable: document, revoked_at: nil).update_all(revoked_at: Time.current, revoked_by_id: @by.id)
      end
    end
    @client.quotes.each do |quote|
      # The approval record keeps what was agreed (the line items and totals in its snapshot) but
      # not who signed or from where. It's signed again as it now is, so it still verifies.
      quote.responses.find_each do |response|
        snapshot = scrub_data(response.snapshot, identifiers)
        response.assign_attributes(signer_name: NAME, email: nil, message: nil, ip_address: nil, user_agent: nil, device: nil, snapshot:,
                                   snapshot_digest: snapshot.present? ? QuoteResponse.digest(snapshot) : response.snapshot_digest)
        response.signature = response.send(:compute_signature)
        QuoteResponse.where(id: response.id).update_all(response.changes.transform_values(&:last)) # read-only through the app
      end
    end
    @client.jobs.find_each do |job|
      job.attachments.purge
      job.update_columns(instructions: nil, internal_notes: nil)
    end
  end

  def erase_requests
    @client.service_requests.find_each do |request|
      request.photos.purge
      request.notes.delete_all
      request.update_columns(contact_name: nil, contact_email: nil, contact_phone: nil, description: nil, address: {})
    end
  end

  def erase_visits
    Visit.joins(:job).where(jobs: { client_id: @client.id }).find_each do |visit|
      visit.photos.purge
      visit.notes.delete_all
      visit.update_columns(instructions: nil, client_note: nil)
    end
  end

  def erase_properties
    @client.properties.update_all(label: nil, address_line1: ADDRESS, address_line2: nil, city: nil, region: nil, postal_code: nil, access_notes: nil)
  end
end
