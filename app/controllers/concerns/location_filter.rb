# CAT-07: lists, the calendar and the dashboard filtered by location, once a business has more
# than one. ?location=<uid> (or "all") changes the filter and is remembered for the member; until
# they choose, it's their home location (as for new documents: their default, else the one location they
# work at), else every location. Visibility
# only: anyone can switch to any location (location-scoped permissions are for later).
#
#   class Admin::QuotesController < Admin::BaseController
#     filters_by_location Quote, only: %i[index search]   # every Quote query in the action
#   end
module LocationFilter
  extend ActiveSupport::Concern

  # How each filterable model reaches its location (built before any scoping applies).
  SCOPES = {
    "ServiceRequest" => ->(location) { ServiceRequest.where(location_id: location.id) },
    "Quote" => ->(location) { Quote.where(location_id: location.id) },
    "Job" => ->(location) { Job.where(location_id: location.id) },
    "Invoice" => ->(location) { Invoice.where(location_id: location.id) },
    "Visit" => ->(location) { Visit.where(job_id: Job.where(location_id: location.id).select(:id)) },
    "Payment" => ->(location) { Payment.where(invoice_id: Invoice.where(location_id: location.id).select(:id)) },
    "QuoteResponse" => ->(location) { QuoteResponse.where(quote_id: Quote.where(location_id: location.id).select(:id)) }
  }.freeze

  included do
    helper_method :location_filter, :location_filter_choices
  end

  class_methods do
    def filters_by_location(*models, **options)
      around_action(**options) { |controller, action| controller.send(:within_location_filter, models, action) }
    end
  end

  private

  # The location being shown, or nil for all of them (and always nil with one location).
  def location_filter
    return @location_filter if defined?(@location_filter)

    @location_filter = nil
    return unless current_membership && current_business.multiple_locations?

    choice = params[:location].to_s
    if choice.present? && (choice == "all" || Location.exists?(uid: choice)) && choice != current_membership.location_filter
      current_membership.update_column(:location_filter, choice)
    end
    stored = current_membership.location_filter
    @location_filter = stored.nil? ? current_membership.home_location : (Location.find_by(uid: stored) unless stored == "all")
  end

  # Active locations, plus the one being shown if it's archived.
  def location_filter_choices = current_business.active_locations.then { location_filter&.archived? ? _1 + [ location_filter ] : _1 }

  def within_location_filter(models, action)
    location = location_filter
    return action.call unless location

    scopes = models.map { SCOPES.fetch(_1.name).call(location) }
    scopes.reverse.inject(action) { |inner, scope| -> { scope.scoping { inner.call } } }.call
  end
end
