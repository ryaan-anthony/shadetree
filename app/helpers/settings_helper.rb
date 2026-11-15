module SettingsHelper
  # Time zones as IANA identifiers, labelled the friendly way and grouped US-first. A current
  # zone the list doesn't name (a valid identifier Rails has no friendly name for) is kept as
  # its own option, so saving other settings never clears it.
  def time_zone_options(current = nil)
    zones = ActiveSupport::TimeZone.all.uniq { _1.tzinfo.identifier }
    us, rest = zones.partition { _1.tzinfo.identifier.start_with?("America/") && ActiveSupport::TimeZone.us_zones.include?(_1) }
    options = {
      "United States" => us.map { [ _1.to_s, _1.tzinfo.identifier ] },
      "Everywhere else" => rest.map { [ _1.to_s, _1.tzinfo.identifier ] }
    }
    identifier = time_zone_identifier(current)
    if identifier && options.values.flatten(1).none? { _1.last == identifier }
      options = { "Current" => [ [ identifier.tr("_", " "), identifier ] ] }.merge(options)
    end
    options
  end

  # "Eastern Time (US & Canada)" and "America/New_York" both select America/New_York.
  def time_zone_identifier(zone) = zone.present? ? ActiveSupport::TimeZone[zone.to_s]&.tzinfo&.identifier : nil

  def currency_options = Money::CURRENCIES.values.map { [ "#{_1.name} (#{_1.code})", _1.code ] }
end
