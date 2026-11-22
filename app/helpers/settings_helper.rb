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
  # its own URL; /admin/settings opens the first one the member can use. A group shows when any
  # of its pages does; each page needs the permission its controller asks for.
  #   settings_groups  # => [["Business", [SettingsPage, ...]], ...] for the current member
  SettingsPage = Data.define(:key, :label, :path)

  # The controllers behind those pages (and their forms), for the sidebar's Settings highlight.
  SETTINGS_CONTROLLERS = %w[businesses hours locations closures tax_rates message_templates custom_message_templates
                            automations payment_accounts plans data_exports].freeze
  def settings_page? = controller_name.in?(SETTINGS_CONTROLLERS) && !(controller_name == "businesses" && action_name.in?(%w[new create]))

  def settings_groups(current = nil) = SettingsHelper.groups_for(current_business, current_membership, self, current:)

  # current: the page being shown, so Locations is listed while adding the first extra one.
  def self.groups_for(business, membership, routes, current: nil)
    can = ->(permission) { membership&.can?(permission) }
    settings = can.(:business_settings)
    [
      [ "Business", ([
        SettingsPage.new("business", "Details", routes.edit_admin_business_path),
        SettingsPage.new("hours", "Hours", routes.admin_hours_path),
        (SettingsPage.new("locations", "Locations", routes.admin_locations_path) if business.multiple_locations? || current == "locations"), # CAT-07
        SettingsPage.new("branding", "Branding", routes.edit_admin_business_path(tab: "branding")),
        SettingsPage.new("request_form", "Request form", routes.edit_admin_business_path(tab: "request_form"))
      ] if settings) ],
      [ "Money", ([
        SettingsPage.new("documents", "Quotes, jobs & invoices", routes.edit_admin_business_path(tab: "documents")),
        SettingsPage.new("taxes", "Taxes", routes.admin_tax_rates_path),
        SettingsPage.new("payments", "Card payments", routes.admin_payment_account_path) # PAY-03
      ] if settings) ],
      [ "Messages", ([
        SettingsPage.new("messages", "Emails to clients", routes.admin_message_templates_path),
        SettingsPage.new("automations", "Automations", routes.admin_automations_path)
      ] if settings) ],
      [ "Plan and data", [
        (SettingsPage.new("plan", "Plan", routes.admin_plan_path) if settings),
        (SettingsPage.new("data", "Your data", routes.admin_data_exports_path) if can.(:export_data))
      ] ]
    ].map { |name, pages| [ name, Array(pages).compact ] }.reject { _2.empty? }
  end
end
