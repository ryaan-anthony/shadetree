# CAT-07: a document that belongs to one of the business's locations (requests, quotes, jobs,
# invoices; visits go by their job's). A new one starts where the document it came from is (a
# quote from a request, a job from a quote, an invoice from a job or quote), else at the
# signed-in member's default location, else the main location.
module AtLocation
  extend ActiveSupport::Concern

  included do
    belongs_to_business_record :location
    before_validation(on: :create) { self.location ||= location_source&.location || default_location }
    validate(on: :update) { errors.add(:location, "is archived. Choose another.") if location_id_changed? && location&.archived? }
  end

  # The location's contact details for client pages, PDFs and emails, falling back to the
  # business's (the main location's are the business's anyway).
  def contact = location || business

  private

  def location_source = nil

  def default_location
    member = Current.membership if Current.membership&.business_id == business_id
    member ? member.document_location : business&.primary_location
  end
end
