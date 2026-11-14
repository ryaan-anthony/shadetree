# Tenant isolation (ADR 0003, ADR 0014). Every business-owned model includes BusinessOwned,
# which scopes every query to Current.business and fails closed when there is none.
module Tenancy
  # A business-owned model was queried with no Current.business. Fix the caller: set the
  # business (controller, job, client link) instead of reaching for the escape hatch.
  class NoBusinessError < StandardError
    def initialize(model)
      super("#{model.name} is business-owned but Current.business is not set. " \
            "Set it, or wrap deliberate cross-business access in Tenancy.across_businesses.")
    end
  end

  class << self
    # The one escape hatch. Grep for `across_businesses` to review every use; each call needs
    # a reason, which is logged. Operator tools (OPS-*), client-link lookups and maintenance
    # jobs are the expected callers.
    def across_businesses(reason:)
      raise ArgumentError, "Tenancy.across_businesses needs a reason" if reason.blank?

      Rails.logger.info("[tenancy] across_businesses: #{reason}")
      previous = Thread.current[:tenancy_across_businesses]
      Thread.current[:tenancy_across_businesses] = true
      yield
    ensure
      Thread.current[:tenancy_across_businesses] = previous
    end

    def across_businesses? = Thread.current[:tenancy_across_businesses] == true

    # Run a block as a business (jobs, scripts, tests).
    def with_business(business, &)
      Current.set(business:, &)
    end
  end
end
