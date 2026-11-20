require "test_helper"
require "server_tls"

# ADR 0023: Puma's HTTPS listener for the tunnel, from the Origin CA certificate and key.
class ServerTlsTest < ActiveSupport::TestCase
  setup do
    @key = OpenSSL::PKey::EC.generate("prime256v1")
    @cert = certificate(@key)
  end

  test "nothing set: no HTTPS listener" do
    assert_nil ServerTls.from_env({})
  end

  test "a matching certificate and key" do
    tls = ServerTls.from_env(env(@cert.to_pem, @key.to_pem))

    assert_equal @cert.to_pem, tls.cert_pem
    assert_equal @key.to_pem, tls.key_pem
  end

  test "refuses one without the other, a key that doesn't match, an expired certificate and bad base64" do
    assert_raises(ServerTls::Error) { ServerTls.from_env("TLS_CERT_BASE64" => Base64.strict_encode64(@cert.to_pem)) }
    other = OpenSSL::PKey::EC.generate("prime256v1")
    assert_raises(ServerTls::Error) { ServerTls.from_env(env(@cert.to_pem, other.to_pem)) }
    assert_raises(ServerTls::Error) { ServerTls.from_env(env(certificate(@key, not_after: Time.now - 60).to_pem, @key.to_pem)) }
    assert_raises(ServerTls::Error) { ServerTls.from_env("TLS_CERT_BASE64" => "not base64!", "TLS_KEY_BASE64" => "x") }
    error = assert_raises(ServerTls::Error) { ServerTls.from_env(env("not a certificate", @key.to_pem)) }
    assert_no_match(/BEGIN/, error.message)
  end

  private
    def env(cert_pem, key_pem) = { "TLS_CERT_BASE64" => Base64.strict_encode64(cert_pem), "TLS_KEY_BASE64" => Base64.strict_encode64(key_pem) }

    def certificate(key, not_after: Time.now + 3600)
      cert = OpenSSL::X509::Certificate.new
      cert.version = 2
      cert.serial = 1
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=shadetree-vm.example.lan")
      cert.public_key = key
      cert.not_before = Time.now - 3600
      cert.not_after = not_after
      cert.sign(key, OpenSSL::Digest.new("SHA256"))
      cert
    end
end
