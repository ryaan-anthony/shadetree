# An invitation to join a business with a role (ACC-03). Sent by email and also shareable as a
# link; expires after 7 days, can be resent (new expiry, same link) or revoked.
class Invitation < ApplicationRecord
  include BusinessOwned

  LIFETIME = 7.days
  TOKEN_LENGTH = 32
  BASE58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".freeze

  belongs_to :invited_by, class_name: "User", optional: true # nil once that user deletes their account
  belongs_to :accepted_by, class_name: "User", optional: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, inclusion: { in: BusinessUser::ROLES }
  validates :invited_by, presence: true, on: :create
  validate :not_already_a_member, on: :create
  validate :not_already_invited, on: :create

  before_validation do
    if new_record?
      self.secret ||= SecureRandom.hex(32)
      self.token_digest ||= self.class.digest(token)
      self.expires_at ||= LIFETIME.from_now
    end
  end

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :expired, -> { where(accepted_at: nil, revoked_at: nil).where("expires_at <= ?", Time.current) }

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

  # The one cross-business lookup for invitations; malformed tokens never reach the database.
  def self.find_by_token(token)
    return nil unless token.is_a?(String) && token.match?(/\A[1-9A-HJ-NP-Za-km-z]{#{TOKEN_LENGTH}}\z/o)

    Tenancy.across_businesses(reason: "invitation lookup") { includes(:business, :invited_by).find_by(token_digest: digest(token)) }
  end

  def token
    number = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "invitation:#{secret}").to_i(16)
    output = +""
    while number.positive?
      number, remainder = number.divmod(58)
      output << BASE58[remainder]
    end
    output.reverse.rjust(TOKEN_LENGTH, "1").first(TOKEN_LENGTH)
  end

  def status
    return :accepted if accepted_at
    return :revoked if revoked_at
    return :expired if expires_at.past?

    :pending
  end

  def pending? = status == :pending

  # The mail job carries plain ids and loads the invitation inside its business (BusinessOwned
  # queries need one), since mail delivery jobs don't restore tenancy themselves.
  def deliver!
    InvitationMailer.with(invitation_id: id, business_id:).invite.deliver_later
    update!(last_sent_at: Time.current)
  end

  def resend!
    update!(expires_at: LIFETIME.from_now)
    deliver!
  end

  def revoke! = update!(revoked_at: Time.current)

  def for?(user) = user.email.casecmp?(email)

  class NotAcceptable < StandardError; end

  # Joins the user to the business with the invited role. Reactivates a deactivated member.
  # Re-reads the invitation under a lock, so a revoke that commits first wins.
  def accept!(user)
    raise NotAcceptable, "This invitation is for #{email}" unless for?(user)

    Tenancy.with_business(business) do
      transaction do
        lock!
        raise NotAcceptable, "This invitation is no longer valid" unless pending?

        membership = BusinessUser.find_or_initialize_by(business:, user:)
        membership.assign_attributes(role:, active: true, deactivated_at: nil) if membership.new_record? || !membership.active?
        membership.save!
        update!(accepted_at: Time.current, accepted_by: user)
        membership
      end
    end
  end

  private

  def not_already_a_member
    member = business&.business_users&.joins(:user)&.find_by("lower(users.email) = ?", email)
    return unless member

    errors.add(:email, member.active? ? "already belongs to a member of this business" :
                                        "belongs to a deactivated member. Reactivate them on the team page instead")
  end

  # Matches the database's uniqueness rule: any invitation not accepted or revoked, expired or not.
  def not_already_invited
    return unless business && Invitation.where(business:, email:, accepted_at: nil, revoked_at: nil).exists?

    errors.add(:email, "already has an invitation. Resend or revoke it from the team page")
  end
end
