# PAY-06: a job an invoice bills. A quote's invoice can bill several of its completed jobs;
# invoices.job_id keeps the first, for links that name one.
class InvoiceJob < ApplicationRecord
  include BusinessOwned

  belongs_to :invoice, inverse_of: :invoice_jobs
  belongs_to_business_record :job

  before_validation { self.business ||= invoice&.business }
end
