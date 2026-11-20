# OPS-05: what Cloudflare Email Routing found when it checked an incoming email, from its own
# Authentication-Results header (the first one; the Worker sends only that, signed). For example
#   mx.cloudflare.net; dkim=pass header.d=example.com …; dmarc=pass header.from=example.com …;
#   spf=pass smtp.mailfrom=bounce@example.com
# Anything else (missing, another server's header, unparseable) passes nothing.
class InboundEmailAuth
  AUTHSERV_ID = "mx.cloudflare.net".freeze

  def self.parse(value) = new(value)

  def initialize(value)
    @results = Hash.new { |hash, key| hash[key] = [] }
    text = value.to_s.gsub(/\([^()]*\)/, " ") # comments can hold anything
    authserv, *methods = text.split(";").map(&:strip)
    return unless authserv.to_s.split.first&.downcase == AUTHSERV_ID

    methods.each do |method|
      name, result = method[/\A([a-z]+)=([a-z]+)/i] && [ $1.downcase, $2.downcase ]
      next unless name

      props = method.scan(/([a-z]+\.[a-z-]+)=("[^"]*"|\S+)/i).to_h { [ _1.downcase, _2.delete('"').downcase ] }
      @results[name] << props.merge("result" => result)
    end
  end

  # DMARC passed for this From domain (DMARC pass means SPF or DKIM passed, aligned with it).
  def dmarc_pass?(from_domain) = @results["dmarc"].any? { _1["result"] == "pass" && _1["header.from"] == from_domain.to_s.downcase }

  # DMARC passed, or DKIM or SPF passed for a domain aligned with the From domain (relaxed).
  def aligned_pass?(from_domain)
    return true if dmarc_pass?(from_domain)

    @results["dkim"].any? { _1["result"] == "pass" && aligned?(_1["header.d"], from_domain) } ||
      @results["spf"].any? { _1["result"] == "pass" && aligned?(_1["smtp.mailfrom"].to_s.split("@").last, from_domain) }
  end

  private

  def aligned?(domain, from_domain)
    domain, from_domain = domain.to_s.downcase, from_domain.to_s.downcase
    return false if domain.blank? || from_domain.blank? || !domain.include?(".")

    domain == from_domain || from_domain.end_with?(".#{domain}") || domain.end_with?(".#{from_domain}")
  end
end
