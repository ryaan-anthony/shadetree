require "test_helper"
require "forwarded_headers"

# ADR 0023: behind the Cloudflare tunnel only the connector may say who the visitor is, and nobody
# may name another host.
class ForwardedHeadersTest < ActiveSupport::TestCase
  CONNECTOR = "192.0.2.20"

  setup do
    @trusted = ForwardedHeaders.proxies("#{CONNECTOR}, 10.9.0.0/16")
    @app = ForwardedHeaders.new(->(env) { [ 200, {}, [ env ] ] }, trusted: @trusted)
  end

  test "the connector's visitor address is kept and becomes remote_ip" do
    env = call("REMOTE_ADDR" => CONNECTOR, "HTTP_X_FORWARDED_FOR" => "203.0.113.9, 198.51.100.7")

    assert_equal "203.0.113.9, 198.51.100.7", env["HTTP_X_FORWARDED_FOR"]
    assert_equal "198.51.100.7", remote_ip(env)
  end

  test "anyone else's forwarded address is dropped, so they count as the client" do
    env = call("REMOTE_ADDR" => "192.0.2.99", "HTTP_X_FORWARDED_FOR" => "203.0.113.9", "HTTP_CLIENT_IP" => "203.0.113.9")

    assert_nil env["HTTP_X_FORWARDED_FOR"]
    assert_nil env["HTTP_CLIENT_IP"]
    assert_equal "192.0.2.99", remote_ip(env)
  end

  test "a range counts, loopback is always trusted, a bad peer address is not" do
    assert call("REMOTE_ADDR" => "10.9.4.2", "HTTP_X_FORWARDED_FOR" => "203.0.113.9")["HTTP_X_FORWARDED_FOR"]
    assert call("REMOTE_ADDR" => "127.0.0.1", "HTTP_X_FORWARDED_FOR" => "203.0.113.9")["HTTP_X_FORWARDED_FOR"]
    assert_nil call("REMOTE_ADDR" => "not an address", "HTTP_X_FORWARDED_FOR" => "203.0.113.9")["HTTP_X_FORWARDED_FOR"]
  end

  test "headers naming another host or port are removed, even from the connector" do
    env = call("REMOTE_ADDR" => CONNECTOR, "HTTP_HOST" => "getshadetree.com", "HTTP_X_FORWARDED_HOST" => "evil.example",
               "HTTP_X_FORWARDED_PORT" => "8080", "HTTP_FORWARDED" => "host=evil.example", "HTTP_X_FORWARDED_SERVER" => "evil.example")

    assert_equal "getshadetree.com", env["HTTP_HOST"]
    %w[HTTP_X_FORWARDED_HOST HTTP_X_FORWARDED_PORT HTTP_FORWARDED HTTP_X_FORWARDED_SERVER].each { assert_nil env[_1], _1 }
  end

  test "a bad TRUSTED_PROXIES entry stops the boot" do
    assert_raises(IPAddr::InvalidAddressError) { ForwardedHeaders.proxies("192.0.2.20, tunnel-vm") }
    assert_equal 2, ForwardedHeaders.proxies("").size
  end

  private
    def call(env) = @app.call(Rack::MockRequest.env_for("/", env)).last.first

    def remote_ip(env)
      ActionDispatch::RemoteIp::GetIp.new(ActionDispatch::Request.new(env), false, @trusted).to_s
    end
end
