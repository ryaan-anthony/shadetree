require "base64"
require "openssl"

# The HTTPS listener's certificate (ADR 0023): the Cloudflare Origin CA certificate for the VM's
# internal hostname, which the tunnel connects to. Read by config/puma.rb, before Rails loads, so
# plain Ruby only. Both values are base64 (the deploy's env file holds one line per value). Without
# them Puma serves plain HTTP only, as in development and test.
module ServerTls
  Config = Data.define(:cert_pem, :key_pem)

  class Error < StandardError; end

  def self.from_env(env = ENV)
    cert, key = env["TLS_CERT_BASE64"].to_s, env["TLS_KEY_BASE64"].to_s
    return if cert.empty? && key.empty?
    raise Error, "set both TLS_CERT_BASE64 and TLS_KEY_BASE64, or neither" if cert.empty? || key.empty?

    cert_pem, key_pem = decode(cert, "TLS_CERT_BASE64"), decode(key, "TLS_KEY_BASE64")
    certificate = OpenSSL::X509::Certificate.new(cert_pem)
    raise Error, "the TLS certificate expired on #{certificate.not_after.utc}" if certificate.not_after < Time.now
    raise Error, "the TLS key does not match the certificate" unless certificate.check_private_key(OpenSSL::PKey.read(key_pem))

    Config.new(cert_pem:, key_pem:)
  rescue OpenSSL::OpenSSLError => error
    raise Error, "the TLS certificate or key can't be read (#{error.class})"
  end

  def self.decode(value, name)
    Base64.strict_decode64(value)
  rescue ArgumentError
    raise Error, "#{name} isn't base64"
  end
end
