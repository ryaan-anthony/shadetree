# Set flag state in tests (PLT-11). Overrides are per thread and cleared after every test.
#
#   with_feature(:new_quote_editor) { get new_admin_quote_path }
#   with_feature(:new_quote_editor, enabled: false) { … }
#   enable_feature(:new_quote_editor)                 # for the rest of the test
#   enable_feature(:x, only: businesses(:one))        # on for one business only
module FeatureFlagHelpers
  def enable_feature(name, only: nil)
    Feature.overrides[name.to_s] = only ? ->(business) { business == only } : true
  end

  def disable_feature(name) = Feature.overrides[name.to_s] = false

  def with_feature(name, enabled: true)
    previous = Feature.overrides.key?(name.to_s) ? Feature.overrides[name.to_s] : :unset
    Feature.overrides[name.to_s] = enabled
    yield
  ensure
    previous == :unset ? Feature.overrides.delete(name.to_s) : Feature.overrides[name.to_s] = previous
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include FeatureFlagHelpers
  teardown { Feature.reset_overrides! }
end
