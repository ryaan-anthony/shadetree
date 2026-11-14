# Release flags: merge unfinished work dark and turn it on for some businesses, a percentage of
# them, or everyone, without a deploy. See CONTRIBUTING.md "Feature flags" and ADR 0015.
#
#   Feature.enabled?(:new_quote_editor)                    # for Current.business
#   Feature.enabled?(:new_quote_editor, business: quote.business)
#   feature?(:new_quote_editor)                            # in views and controllers
#
#   Feature.enable!(:new_quote_editor)                     # everyone
#   Feature.enable_for!(:new_quote_editor, business)       # add one business
#   Feature.enable_percentage!(:new_quote_editor, 25)      # 25% of businesses, stable per business
#   Feature.disable!(:new_quote_editor)                    # kill switch
module Feature
  class UnknownFlag < StandardError; end

  Definition = Data.define(:name, :description, :owner, :remove_by)

  CACHE_TTL = 30.seconds

  class << self
    def definitions
      @definitions ||= load_definitions
    end

    def defined?(name) = definitions.key?(name.to_s)

    def enabled?(name, business: Current.business)
      name = name.to_s
      return override_for(name) if overrides.key?(name)
      return report_unknown(name) unless self.defined?(name)

      state_for(name)&.enabled_for?(business) || false
    end

    def enable!(name, by: nil) = update!(name, state: "on", changed_by: by)
    def disable!(name, by: nil) = update!(name, state: "off", business_ids: [], percentage: 0, changed_by: by)

    def enable_for!(name, business, by: nil)
      flag = record(name)
      ids = (flag.business_ids | [ business.id ])
      update!(name, state: flag.state == "on" ? "on" : "businesses", business_ids: ids, changed_by: by)
    end

    def disable_for!(name, business, by: nil)
      flag = record(name)
      ids = flag.business_ids - [ business.id ]
      state = flag.state == "businesses" && ids.empty? ? "off" : flag.state
      update!(name, state:, business_ids: ids, changed_by: by)
    end

    def enable_percentage!(name, percentage, by: nil)
      update!(name, state: "percentage", percentage: Integer(percentage), changed_by: by)
    end

    # Stable 0-99 bucket per flag and business, so a business keeps its answer as the
    # percentage grows and different flags don't pick the same businesses.
    def bucket(name, business) = Zlib.crc32("#{name}:#{business.id}") % 100

    def cache_key(name) = "feature_flags/#{name}"

    # Rows for every declared flag, with their stored state (or off).
    def status
      stored = FeatureFlag.where(name: definitions.keys).index_by(&:name)
      definitions.values.map { |definition| [ definition, stored[definition.name] || FeatureFlag.new(name: definition.name) ] }
    end

    # Test support: force a flag on or off for the current thread. See FeatureFlagHelpers.
    def overrides = Thread.current[:feature_overrides] ||= {}
    def reset_overrides! = Thread.current[:feature_overrides] = {}

    def reload_definitions! = @definitions = nil

    private

    def record(name)
      name = name.to_s
      raise UnknownFlag, "#{name} is not declared in config/feature_flags.yml" unless self.defined?(name)

      FeatureFlag.find_or_initialize_by(name:)
    end

    def update!(name, **attributes)
      record(name).tap { |flag| flag.update!(attributes) }
    end

    def state_for(name)
      Rails.cache.fetch(cache_key(name), expires_in: CACHE_TTL) { FeatureFlag.find_by(name:) }
    end

    def override_for(name)
      value = overrides[name]
      value.respond_to?(:call) ? value.call(Current.business) : value
    end

    def report_unknown(name)
      message = "Feature flag #{name.inspect} is not declared in config/feature_flags.yml"
      raise UnknownFlag, message if Rails.env.test?

      Rails.logger.warn("[feature] #{message}; treating it as off")
      false
    end

    def load_definitions
      raw = YAML.safe_load_file(Rails.root.join("config/feature_flags.yml")) || {}
      raw.to_h.to_h do |name, attributes|
        attributes = attributes.to_h.transform_keys(&:to_s)
        missing = %w[description owner remove_by] - attributes.keys
        raise ArgumentError, "Feature flag #{name} needs #{missing.join(", ")}" if missing.any?

        [ name.to_s, Definition.new(name: name.to_s, **attributes.slice("description", "owner", "remove_by").transform_keys(&:to_sym)) ]
      end.freeze
    end
  end
end
