module SettingsHelper
  # Time zones as IANA identifiers, labelled the friendly way and grouped US-first.
  def time_zone_options
    zones = ActiveSupport::TimeZone.all.uniq { _1.tzinfo.identifier }
    us, rest = zones.partition { _1.tzinfo.identifier.start_with?("America/") && ActiveSupport::TimeZone.us_zones.include?(_1) }
    {
      "United States" => us.map { [ _1.to_s, _1.tzinfo.identifier ] },
      "Everywhere else" => rest.map { [ _1.to_s, _1.tzinfo.identifier ] }
    }
  end

  def currency_options = Money::CURRENCIES.values.map { [ "#{_1.name} (#{_1.code})", _1.code ] }
end
