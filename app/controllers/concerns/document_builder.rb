# What the quote and invoice builders share (QTE-01, PAY-01): moving a draft to another client,
# its property, and the tax rates the builder ticked. The controller defines `builder_document`
# (the quote or invoice being built) and sets @client_changed through change_client.
module DocumentBuilder
  extend ActiveSupport::Concern

  included do
    helper_method :tax_rate_key
  end

  private

  # After a client change, a submitted property only counts if it's the new client's (the
  # selector may already show the new client's properties); otherwise keep the new default.
  def assign_property(uid)
    property = builder_document.client.properties.find_by(uid:) if uid.present?
    return if @client_changed && property.nil?

    builder_document.property = property
  end

  # Moving a draft to another client resets its property, and its taxes when exemption differs.
  def change_client(uid)
    client = Client.active.find_by(uid:) or return
    document = builder_document
    exempt_changed = client.tax_exempt != document.client.tax_exempt
    document.client = client
    document.property = client.primary_property
    document.tax_rate_list = TaxRate.for_new_document(client:, location: document.location) if exempt_changed
    @client_changed = true
  end

  # Tax rates the builder ticked, by "name|percent": the business's active rates plus any the
  # document already had (so an archived rate on an old draft can stay).
  def chosen_tax_rates(keys)
    available = (TaxRate.active.ordered.map(&:to_pricing) + builder_document.tax_rate_list).uniq
    wanted = Array(keys).compact_blank
    available.select { wanted.include?(tax_rate_key(_1)) }
  end

  def tax_rate_key(rate) = "#{rate.name}|#{rate.percent.to_d.to_s("F")}"
end
