# NTF-03: what each placeholder is filled with, from the records an email is about. Money and
# dates are formatted the way the emails show them.
module MessageTemplate::Values
  extend self

  def client(client, name: nil)
    full = name.presence || client&.display_name.to_s
    { "client_name" => full, "client_first_name" => full.split.first.to_s }
  end

  def business(business) = { "business_name" => business.name, "next_steps" => business.quote_next_steps }

  def sender(user, business) = { "your_name" => user&.first_name.presence || business.name }

  def quote(quote, link: nil)
    client(quote.client).merge(business(quote.business)).merge(
      "quote_number" => quote.number, "quote_title" => quote.title.to_s, "document_number" => quote.number, "document_title" => quote.title.to_s, "total" => quote.totals.total.format,
      "valid_until" => quote.expires_on&.to_fs(:long).to_s, "link" => link_url(link)
    )
  end

  def invoice(invoice, link: nil, balance: invoice.balance)
    client(invoice.client).merge(business(invoice.business)).merge(
      "invoice_number" => invoice.number, "invoice_title" => invoice.title.to_s, "document_number" => invoice.number, "document_title" => invoice.title.to_s, "total" => invoice.totals.total.format,
      "balance" => balance.format, "due_date" => invoice.due_on&.to_fs(:long).to_s, "link" => link_url(link)
    )
  end

  def visit(job, when_label) = client(job.client).merge(business(job.business)).merge("visit_window" => when_label.to_s)

  # JOB-12: "Marcus and Dee are on the way" (or the business's name) and "about 11:15 am".
  def on_the_way(visit, arrives_at: visit.on_the_way_arrives_at || 30.minutes.from_now)
    names = visit.on_the_way_team.map(&:client_first_name)
    { "on_the_way" => "#{names.any? ? names.to_sentence : visit.business.name} #{names.size > 1 ? "are" : "is"} on the way",
      "arrival_time" => "about #{visit.on_the_way_time_label(OnTheWay.round_to_five(arrives_at))}" }
  end

  def request(request) = client(request.client, name: request.contact_name).merge(business(request.business))

  # The values for a real record, for the editor's preview (and manual sends).
  def for_record(record, user:)
    values = case record
    when Quote then quote(record).merge("signer_name" => record.approval&.signer_name.to_s)
    when Invoice then invoice(record)
    when Visit then visit(record.job, record.when_label).merge(on_the_way(record))
    when ServiceRequest then request(record)
    else raise ArgumentError, "No message values for #{record.class}"
    end
    values.merge(sender(user, record.business))
  end

  private

  def link_url(link) = link ? Rails.application.routes.url_helpers.client_link_url(link.token, **ActionMailer::Base.default_url_options) : ""
end
