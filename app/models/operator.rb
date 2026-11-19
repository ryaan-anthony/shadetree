# Someone who runs Shadetree (OPS-01): a grant on a user, separate from any business
# membership, that opens the operator console once they've verified with two-factor. The
# first operator comes from `bin/rails ops:grant EMAIL=…`; operators grant and revoke others.
class Operator < ApplicationRecord
  RECOVERY_CODES = 10

  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  scope :active, -> { where(revoked_at: nil) }

  class LastOperator < StandardError; end

  def self.for(user) = user && active.find_by(user:)

  def self.grant!(user, by: nil)
    operator = find_or_initialize_by(user:)
    operator.update!(granted_by: by, revoked_at: nil, revoked_by: nil)
    operator
  end

  def active? = revoked_at.nil?

  def revoke!(by:)
    transaction do
      self.class.active.lock.load # serialize grants and revokes
      raise LastOperator, "The last operator can't be revoked." if self.class.active.where.not(id:).none?

      update!(revoked_at: Time.current, revoked_by: by, otp_secret_ciphertext: nil, otp_enabled_at: nil, recovery_code_digests: [])
    end
  end

  # Two-factor. The secret is stored encrypted; it's set when enrolling and confirmed by a code.
  def two_factor? = otp_enabled_at.present?

  def otp_secret = otp_secret_ciphertext && self.class.encryptor.decrypt_and_verify(otp_secret_ciphertext)
  def otp_secret=(secret)
    self.otp_secret_ciphertext = secret && self.class.encryptor.encrypt_and_sign(secret)
  end

  def start_enrollment! = update!(otp_secret: Totp.random_secret, otp_enabled_at: nil, otp_last_step: nil)

  # Confirms enrollment with a first code; returns the recovery codes (shown once) or nil.
  def enable_two_factor!(code)
    step = otp_secret && Totp.verify(otp_secret, code)
    return nil unless step

    codes = Array.new(RECOVERY_CODES) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }
    update!(otp_enabled_at: Time.current, otp_last_step: step, recovery_code_digests: codes.map { digest(_1) })
    codes
  end

  # A code from the app (each works once), or a recovery code (used up).
  def verify_two_factor(code)
    return false unless two_factor?

    with_lock do
      if (step = Totp.verify(otp_secret, code, after: otp_last_step))
        update!(otp_last_step: step)
      elsif (used = recovery_code_digests.find { ActiveSupport::SecurityUtils.secure_compare(_1, digest(code.to_s.strip.downcase)) })
        update!(recovery_code_digests: recovery_code_digests - [ used ])
      else
        return false
      end
    end
    true
  end

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("operator two-factor", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end

  private

  def digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code)
end
