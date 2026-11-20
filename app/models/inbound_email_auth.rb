# OPS-05: what Cloudflare Email Routing found when it checked an incoming email, from its own
# Authentication-Results header (the first one; the Worker sends only that, signed). For example
#   mx.cloudflare.net; dkim=pass header.d=example.com …; dmarc=pass header.from=example.com …;
#   spf=pass smtp.mailfrom=bounce@example.com
# Anything else (missing, another server's header, unparseable, or with a "," outside quotes and
# comments, which means headers were joined) passes nothing.
class InboundEmailAuth
  AUTHSERV_ID = "mx.cloudflare.net".freeze

  def self.parse(value) = new(value)

  def initialize(value)
    @results = Hash.new { |hash, key| hash[key] = [] }
    # Quoted strings (a sender-chosen smtp.mailfrom local part) and comments can hold anything,
    # even "; dmarc=pass": blank them before splitting.
    text = value.to_s.gsub(/"(?:[^"\\]|\\.)*"/, '""').gsub(/\([^()]*\)/, " ")
    return if text.include?(",")

    authserv, *methods = text.split(";").map(&:strip)
    return unless authserv.to_s.split.first&.downcase == AUTHSERV_ID

    methods.each do |method|
      name, result = method[/\A([a-z]+)=([a-z]+)/i] && [ $1.downcase, $2.downcase ]
      next unless name

      props = method.scan(/([a-z]+\.[a-z-]+)=(\S+)/i).to_h { [ _1.downcase, _2.delete('"').downcase ] }
      @results[name] << props.merge("result" => result)
    end
  end

  # DMARC passed for this From domain (DMARC pass means SPF or DKIM passed, aligned with it).
  # Only Cloudflare's first DMARC and SPF results count (there is one of each).
  def dmarc_pass?(from_domain) = @results["dmarc"].first(1).any? { _1["result"] == "pass" && _1["header.from"] == from_domain.to_s.downcase }

  # DMARC passed, or DKIM or SPF passed for a domain aligned with the From domain (relaxed).
  def aligned_pass?(from_domain)
    return true if dmarc_pass?(from_domain)

    @results["dkim"].any? { _1["result"] == "pass" && aligned?(_1["header.d"], from_domain) } ||
      @results["spf"].first(1).any? { _1["result"] == "pass" && aligned?(_1["smtp.mailfrom"].to_s.split("@").last, from_domain) }
  end

  private

  # Relaxed alignment by suffix, without a public-suffix list: good enough only because a reply
  # also needs the signed reply address and the right From, and new tickets need DMARC pass.
  def aligned?(domain, from_domain)
    domain, from_domain = domain.to_s.downcase, from_domain.to_s.downcase
    return false if domain.blank? || from_domain.blank? || !domain.include?(".")

    domain == from_domain || from_domain.end_with?(".#{domain}") || domain.end_with?(".#{from_domain}")
  end
end
