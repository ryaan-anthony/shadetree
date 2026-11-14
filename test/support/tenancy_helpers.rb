# Helpers every business-owned feature uses to prove isolation (PLT-06, ADR 0014).
#
# Model tests:
#   as_business(businesses(:one)) { Client.create!(name: "Ana") }
#
# Integration tests: a member of business A asking for business B's record gets 404,
# whether by URL or by an id smuggled into a form:
#   assert_not_found_across_businesses { get admin_client_path(other_client) }
#   assert_not_found_across_businesses { patch admin_quote_path(quote), params: { quote: { client_id: other_client.id } } }
module TenancyHelpers
  def as_business(business, &) = Tenancy.with_business(business, &)

  # Build or look up records in another business without leaking Current into the test.
  def in_other_business(business, &)
    previous = Current.business
    Current.business = business
    yield
  ensure
    Current.business = previous
  end

  def assert_not_found_across_businesses(message = "Expected 404 for another business's record")
    yield
    assert_response :not_found, message
  end
end

ActiveSupport.on_load(:active_support_test_case) { include TenancyHelpers }
