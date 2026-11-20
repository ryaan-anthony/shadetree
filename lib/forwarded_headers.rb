require "ipaddr"

# Forwarded headers in production (ADR 0023). The Cloudflare tunnel connector passes the browser's
# Host header through and adds the visitor's address in X-Forwarded-For. Rails reads
# X-Forwarded-For for request.remote_ip (the key of every per-IP rate limit) even when the peer
# that sent it is not a trusted proxy, and prefers X-Forwarded-Host over Host. So, first in the
# middleware stack:
# - headers that name another host or port are always removed: nothing in front of the app sets them;
# - the client-address headers are kept only from a trusted proxy (TRUSTED_PROXIES: the tunnel
#   connector's address), and removed from anyone else, who then counts as the client.
class ForwardedHeaders
  HOST_HEADERS = %w[HTTP_X_FORWARDED_HOST HTTP_X_FORWARDED_PORT HTTP_X_FORWARDED_SERVER HTTP_FORWARDED].freeze
  CLIENT_HEADERS = %w[HTTP_X_FORWARDED_FOR HTTP_CLIENT_IP].freeze
  LOOPBACK = [ IPAddr.new("127.0.0.0/8"), IPAddr.new("::1") ].freeze

  # "192.0.2.20, 10.0.5.0/24" -> loopback plus those ranges. A bad entry raises, so a typo stops
  # the boot instead of trusting nothing (or everything) quietly.
  def self.proxies(list)
    LOOPBACK + list.to_s.split(",").map(&:strip).reject(&:empty?).map { IPAddr.new(_1) }
  end

  def initialize(app, trusted:)
    @app = app
    @trusted = trusted
  end

  def call(env)
    HOST_HEADERS.each { env.delete(_1) }
    CLIENT_HEADERS.each { env.delete(_1) } unless trusted?(env["REMOTE_ADDR"])
    @app.call(env)
  end

  private
    def trusted?(address)
      ip = IPAddr.new(address.to_s)
      @trusted.any? { _1.include?(ip) }
    rescue IPAddr::Error
      false
    end
end
