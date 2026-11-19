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
      "quote_number" => quote.number, "quote_title" => quote.title.to_s, "total" => quote.totals.total.format,
      "valid_until" => quote.expires_on&.to_fs(:long).to_s, "link" => link_url(link)
    )
  end

  def invoice(invoice, link: nil, balance: invoice.balance)
    client(invoice.client).merge(business(invoice.business)).merge(
      "invoice_number" => invoice.number, "invoice_title" => invoice.title.to_s, "total" => invoice.totals.total.format,
      "balance" => balance.format, "due_date" => invoice.due_on&.to_fs(:long).to_s, "link" => link_url(link)
    )
  end

  def visit(job, when_label) = client(job.client).merge(business(job.business)).merge("visit_window" => when_label.to_s)

  def request(request) = client(request.client, name: request.contact_name).merge(business(request.business))

  private

  def link_url(link) = link ? Rails.application.routes.url_helpers.client_link_url(link.token, **ActionMailer::Base.default_url_options) : ""
end
