# ACC-08: a one-line tip the first time a member opens each main page, once per person per
# business. Which page gets which tip, and who can see it; wording: config/locales/guidance.en.yml.
#
#   FirstTimeTips.for(membership, "admin/quotes", "edit")  # => "quote_builder", or nil
module FirstTimeTips
  # key => [the pages (controller#action) it shows on, the permission it needs]
  PAGES = {
    "requests" => [ %w[admin/service_requests#index], :office ],
    "quote_builder" => [ %w[admin/quotes#new admin/quotes#edit], :office ],
    "send" => [ %w[admin/quote_sends#new], :office ],
    "schedule" => [ %w[admin/schedule#show], :schedule ],
    "invoices" => [ %w[admin/invoices#index], :office ],
    "services" => [ %w[admin/catalog_items#index], :business_settings ],
    "settings" => [ %w[admin/businesses#edit], :business_settings ]
  }.freeze
  KEYS = PAGES.keys.freeze

  # The tip for this page, if the member can use it, hasn't seen it, and hasn't turned tips off.
  def self.for(membership, controller_path, action)
    return unless membership&.active? && !membership.user.tips_off?

    page = "#{controller_path}##{action}"
    key, (_, permission) = PAGES.find { |_, (pages, _)| pages.include?(page) }
    key if key && membership.can?(permission) && !membership.tips.key?(key)
  end

  def self.text(key) = I18n.t("guidance.tips.#{key}")
end
