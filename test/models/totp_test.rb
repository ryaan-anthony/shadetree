require "test_helper"

# OPS-01: one-time codes as authenticator apps make them (RFC 6238's SHA-1 test vectors).
class TotpTest < ActiveSupport::TestCase
  SECRET = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" # base32 of "12345678901234567890"

  test "matches the RFC 6238 test vectors (last six digits)" do
    { 59 => "287082", 1_111_111_109 => "081804", 1_234_567_890 => "005924", 2_000_000_000 => "279037" }.each do |time, code|
      assert_equal code, Totp.code(SECRET, time / 30)
    end
  end

  test "verifies within one step, not a reused or wrong code" do
    at = Time.zone.at(1_234_567_890)
    step = 1_234_567_890 / 30
    assert_equal step, Totp.verify(SECRET, "005924", at:)
    assert_equal step, Totp.verify(SECRET, "005 924", at: at + 25.seconds)
    assert_nil Totp.verify(SECRET, "005924", at: at + 2.minutes)
    assert_nil Totp.verify(SECRET, "005924", at:, after: step)
    assert_nil Totp.verify(SECRET, "abcdef", at:)
    assert_match %r{\Aotpauth://totp/Shadetree%3Aa%40b.co\?secret=#{SECRET}}, Totp.uri(SECRET, account: "a@b.co")
  end
end
