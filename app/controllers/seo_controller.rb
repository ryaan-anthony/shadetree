# MKT-04: robots.txt and the sitemap. The staff app, the operator console, sign-in pages and
# client links stay out of search engines; public marketing pages, and request pages of
# businesses that chose to be found, are listed.
class SeoController < ApplicationController
  PAGES = %i[root_path features_path pricing_path about_path contact_path terms_path privacy_path].freeze
  PRIVATE = %w[/admin /ops /c/ /users/ /rails/ /up].freeze

  def robots
    lines = [ "User-agent: *", *PRIVATE.map { "Disallow: #{_1}" }, "", "Sitemap: #{helpers.public_base_url}/sitemap.xml" ]
    expires_in 1.hour, public: true
    render plain: lines.join("\n") + "\n"
  end

  def sitemap
    base = helpers.public_base_url
    @urls = PAGES.map { "#{base}#{public_send(_1)}" }
    @urls += Business.active.where(request_form_enabled: true, request_form_indexable: true).order(:id).pluck(:handle)
                     .map { "#{base}#{public_request_path(_1)}" }
    expires_in 1.hour, public: true
    render formats: :xml
  end
end
