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
  def meta_index? = @page_meta.nil? || @page_meta[:index]

  # The address this page should be known by: the public host, the path, no query string.
  def canonical_url = "#{public_base_url}#{request.path == "/" ? "/" : request.path.chomp("/")}"

  def share_image_url = "#{public_base_url}#{image_path(@page_meta&.dig(:image) || "marketing/share.png")}"

  def public_base_url
    options = Rails.application.config.action_mailer.default_url_options || {}
    host = options[:host].presence or return request.base_url
    port = options[:port] ? ":#{options[:port]}" : ""
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
        "offers" => plans.map { { "@type" => "Offer", "name" => _1.name, "price" => format("%.2f", _1.monthly_price_cents / 100.0), "priceCurrency" => _1.currency } } }
    ]
    tag.script(data.to_json.html_safe, type: "application/ld+json", nonce: content_security_policy_nonce) # rubocop:disable Rails/OutputSafety -- JSON, escaped by to_json
  end
end
