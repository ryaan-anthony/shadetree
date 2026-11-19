# MKT-04: what search engines and link previews read from a public page: a unique title and
# description, the canonical address, Open Graph / Twitter cards with the share image, and
# whether the page may be indexed.
#
#   <% page_meta description: "Plans and prices…" %>        # in a marketing view
#   <% page_meta description: "…", index: false %>          # kept out of search engines
module SeoHelper
  SITE = "Shadetree"
  DEFAULT_DESCRIPTION = "Send professional quotes, get them approved online, schedule the work and get paid. Free to start, no card needed."

  def page_meta(description:, index: true, image: nil)
    @page_meta = { description:, index:, image: }
    nil
  end

  def meta_description = @page_meta&.dig(:description) || DEFAULT_DESCRIPTION
  # Only pages that describe themselves (page_meta) are indexed; anything else is kept out.
  def meta_index? = @page_meta.present? && @page_meta[:index]

  # "Pricing · Shadetree", escaped once.
  def page_title = safe_join([ content_for(:title).presence, SITE ].compact.uniq, " · ")

  # The address this page should be known by: the public host, the path, no query string.
  def canonical_url = "#{public_base_url}#{request.path == "/" ? "/" : request.path.chomp("/")}"

  def share_image_url = URI.join("#{public_base_url}/", image_path(@page_meta&.dig(:image) || "marketing/share.jpg")).to_s

  # The public host: APP_HOST (as PDFs use it), else the mailer's. A production app without a
  # real host falls back to the request's rather than pointing search engines at example.com.
  def public_base_url
    options = Rails.application.config.action_mailer.default_url_options || {}
    host = ENV["APP_HOST"].presence || options[:host].presence
    if host.nil? || (Rails.env.production? && host == "example.com")
      Rails.logger.warn("[seo] APP_HOST isn't set; using the request's host") if Rails.env.production?
      return request.base_url
    end
    port = options[:port] && !ENV["APP_HOST"].present? ? ":#{options[:port]}" : ""
    "#{options[:protocol] || request.protocol.delete_suffix("://")}://#{host}#{port}"
  end

  # Structured data for the home page: the organization, and the product with its plans' prices.
  def structured_data(plans)
    base = public_base_url
    data = [
      { "@context" => "https://schema.org", "@type" => "Organization", "name" => SITE, "url" => "#{base}/",
        "logo" => "#{base}/icon.png" },
      { "@context" => "https://schema.org", "@type" => "SoftwareApplication", "name" => SITE, "url" => "#{base}/",
        "applicationCategory" => "BusinessApplication", "operatingSystem" => "Web",
        "description" => DEFAULT_DESCRIPTION,
        "offers" => plans.map do |plan|
          { "@type" => "Offer", "name" => plan.name, "price" => plan.monthly_price.to_s, "priceCurrency" => plan.currency,
            "priceSpecification" => { "@type" => "UnitPriceSpecification", "price" => plan.monthly_price.to_s,
                                      "priceCurrency" => plan.currency, "billingDuration" => "P1M" } }
        end }
    ]
    tag.script(data.to_json.html_safe, type: "application/ld+json", nonce: content_security_policy_nonce) # rubocop:disable Rails/OutputSafety -- JSON, escaped by to_json
  end
end
