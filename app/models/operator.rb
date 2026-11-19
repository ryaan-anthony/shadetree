# Someone who runs Shadetree (OPS-01): a grant on a user, separate from any business
# membership, that opens the operator console once they've verified with two-factor. The
# first operator comes from `bin/rails ops:grant EMAIL=…`; operators grant and revoke others.
class Operator < ApplicationRecord
  RECOVERY_CODES = 10
  # Wrong codes in a row before codes stop being checked for LOCK_DURATION. With the
  # controller's rate limit, that's a few dozen guesses a day against a 1-in-a-million chance.
  MAX_FAILED_ATTEMPTS = 10
  LOCK_DURATION = 1.hour
  # A secret shown on the setup page but not confirmed by then is replaced on the next visit.
  ENROLLMENT_TTL = 15.minutes

  belongs_to :user
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  scope :active, -> { where(revoked_at: nil) }

  class LastOperator < StandardError; end

  def self.for(user) = user && active.find_by(user:)

  # Grants (or re-grants) access. Two people granting the same user at once both succeed.
  def self.grant!(user, by: nil)
    operator = find_or_initialize_by(user:)
    operator.update!(granted_by: by, revoked_at: nil, revoked_by: nil)
    operator
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def active? = revoked_at.nil?

  def revoke!(by:)
    transaction do
      self.class.active.lock.load # serialize grants and revokes
      raise LastOperator, "The last operator can't be revoked." if self.class.active.where.not(id:).none?

      update!(revoked_at: Time.current, revoked_by: by, **TWO_FACTOR_CLEARED)
    end
  end

  def last_active? = active? && self.class.active.where.not(id:).none?

  # Two-factor. The secret is stored encrypted; it's set when enrolling and confirmed by a code.
  TWO_FACTOR_CLEARED = { otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_started_at: nil, otp_last_step: nil,
                         recovery_code_digests: [], failed_attempts: 0, locked_until: nil }.freeze

  def two_factor? = otp_enabled_at.present?

  def otp_secret = otp_secret_ciphertext && self.class.encryptor.decrypt_and_verify(otp_secret_ciphertext)
  def otp_secret=(secret)
    self.otp_secret_ciphertext = secret && self.class.encryptor.encrypt_and_sign(secret)
  end

  # The secret to show on the setup page: the one in progress, or a new one if there's none or
  # it went unconfirmed too long.
  def enrollment_secret!
    if otp_secret_ciphertext.nil? || otp_started_at.nil? || otp_started_at < ENROLLMENT_TTL.ago
      update!(otp_secret: Totp.random_secret, otp_started_at: Time.current, otp_enabled_at: nil, otp_last_step: nil)
    end
    otp_secret
  end

  # For a lost phone: the operator sets up two-factor again on their next visit.
  def reset_two_factor! = update!(TWO_FACTOR_CLEARED)

  def locked? = locked_until&.future?

  # Confirms enrollment with a first code; returns the recovery codes (shown once) or nil.
  def enable_two_factor!(code)
    with_lock do
      next nil if two_factor? || locked? || otp_started_at.nil? || otp_started_at < ENROLLMENT_TTL.ago

      step = otp_secret && Totp.verify(otp_secret, code)
      next failed! unless step

      codes = new_recovery_codes
      update!(otp_enabled_at: Time.current, otp_last_step: step, recovery_code_digests: codes.map { digest(_1) }, failed_attempts: 0)
      codes
    end
  end

  # A code from the app (each works once) or a recovery code (used up): :app, :recovery, or
  # false. Nothing is checked while locked.
  def verify_two_factor(code)
    return false unless two_factor?

    with_lock do
      next false if locked?

      if (step = Totp.verify(otp_secret, code, after: otp_last_step))
        update!(otp_last_step: step, failed_attempts: 0)
        :app
      elsif (used = recovery_code_digest_for(code))
        update!(recovery_code_digests: recovery_code_digests - [ used ], failed_attempts: 0)
        :recovery
      else
        failed!
        false
      end
    end
  end

  def recovery_codes_left = recovery_code_digests.size

  # A fresh set of recovery codes, replacing the old ones. Returns them (shown once).
  def regenerate_recovery_codes!
    codes = new_recovery_codes
    update!(recovery_code_digests: codes.map { digest(_1) })
    codes
  end

  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key("operator two-factor", 32))
  end

  private

  def failed!
    attempts = failed_attempts + 1
    if attempts >= MAX_FAILED_ATTEMPTS
      update!(failed_attempts: 0, locked_until: LOCK_DURATION.from_now)
    else
      update!(failed_attempts: attempts)
    end
    nil
  end

  def new_recovery_codes = Array.new(RECOVERY_CODES) { SecureRandom.alphanumeric(10).downcase.scan(/.{5}/).join("-") }

  # Typed with or without the dash, in any case.
  def recovery_code_digest_for(code)
    plain = code.to_s.downcase.gsub(/[^a-z0-9]/, "")
    return unless plain.size == 10

    typed = digest("#{plain[0, 5]}-#{plain[5, 5]}")
    recovery_code_digests.find { ActiveSupport::SecurityUtils.secure_compare(_1, typed) }
  end

  def digest(code) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, code)
end
