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

  # #289: Settings in four groups, each page where an owner would look for it. Every page keeps
  # its own URL; /admin/settings opens the first. A group shows when any of its pages does.
  #   settings_groups  # => [["Business", [[key, label, path], ...]], ...] for the current member
  SettingsPage = Data.define(:key, :label, :path)

  def settings_groups
    business = current_business
    can = ->(permission) { current_membership&.can?(permission) }
    [
      [ "Business", [
        SettingsPage.new("business", "Details", edit_admin_business_path),
        SettingsPage.new("hours", "Hours", admin_hours_path),
        (SettingsPage.new("locations", "Locations", admin_locations_path) if business.multiple_locations?), # CAT-07
        SettingsPage.new("branding", "Branding", edit_admin_business_path(tab: "branding")),
        SettingsPage.new("request_form", "Request form", edit_admin_business_path(tab: "request_form"))
      ] ],
      [ "Money", [
        SettingsPage.new("documents", "Quotes, jobs & invoices", edit_admin_business_path(tab: "documents")),
        SettingsPage.new("taxes", "Taxes", admin_tax_rates_path),
        SettingsPage.new("payments", "Online payments", admin_payment_account_path) # PAY-03
      ] ],
      [ "Messages", [
        SettingsPage.new("messages", "Emails to clients", admin_message_templates_path),
        SettingsPage.new("automations", "Automations", admin_automations_path)
      ] ],
      [ "Plan and data", [
        SettingsPage.new("plan", "Plan", admin_plan_path),
        (SettingsPage.new("data", "Your data", admin_data_exports_path) if can.(:export_data))
      ] ]
    ].map { |name, pages| [ name, pages.compact ] }.reject { _2.empty? }
  end
end
