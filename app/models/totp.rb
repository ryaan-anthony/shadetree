# Time-based one-time passwords (RFC 6238, as authenticator apps use: SHA-1, 6 digits, 30-second
# steps), for operator two-factor (OPS-01). Small enough to keep in the app rather than add a
# dependency.
#
#   secret = Totp.random_secret                 # base32, shown once as a QR code
#   Totp.uri(secret, account: email)            # otpauth:// for the QR code
#   Totp.verify(secret, "123456", after: last)  # => the time step it matched, or nil
module Totp
  DIGITS = 6
  STEP = 30
  DRIFT = 1 # accept the codes just before and after now
  BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  module_function

  def random_secret = Array.new(32) { BASE32[SecureRandom.random_number(32)] }.join

  def uri(secret, account:, issuer: "Shadetree")
    label = ERB::Util.url_encode("#{issuer}:#{account}")
    "otpauth://totp/#{label}?secret=#{secret}&issuer=#{ERB::Util.url_encode(issuer)}&digits=#{DIGITS}&period=#{STEP}"
  end

  def code(secret, step)
    hmac = OpenSSL::HMAC.digest("SHA1", decode(secret), [ step ].pack("Q>"))
    offset = hmac.bytes.last & 0x0f
    value = (hmac.byteslice(offset, 4).unpack1("N") & 0x7fffffff) % (10**DIGITS)
    value.to_s.rjust(DIGITS, "0")
  end

  # The step a code matches (within DRIFT of now and after `after`, so a code works once).
  def verify(secret, given, at: Time.current, after: nil)
    given = given.to_s.gsub(/\s/, "")
    return nil unless given.match?(/\A\d{#{DIGITS}}\z/o)

    now = at.to_i / STEP
    (now - DRIFT..now + DRIFT).find do |step|
      (after.nil? || step > after) && ActiveSupport::SecurityUtils.secure_compare(code(secret, step), given)
    end
  end

  def decode(secret)
    bits = secret.upcase.delete("=").each_char.map { BASE32.index(_1).to_s(2).rjust(5, "0") }.join
    [ bits[0, bits.length / 8 * 8] ].pack("B*")
  end
end
