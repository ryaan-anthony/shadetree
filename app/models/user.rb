# User accounts for business owners, staff, and customers.
#
# The User model represents all user accounts in the Shadetree platform,
# including business owners, staff members, and customers. Users can be
# associated with businesses and have various roles within the system.
#
# @attr [String] email User email (required, unique)
# @attr [String] encrypted_password Encrypted password (required)
# @attr [String] first_name First name
# @attr [String] last_name Last name
# @attr [String] reset_password_token Password reset token
# @attr [DateTime] reset_password_sent_at Password reset timestamp
# @attr [DateTime] remember_created_at Remember me timestamp
class User < ApplicationRecord
  # ACC-01: unconfirmed users may sign in (config.allow_unconfirmed_access_for = nil) but can't
  # send to clients; repeated failures lock the account (lockable, unlock by email or time).
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable, :lockable

  # Sign-up form checkbox; stored as terms_accepted_at.
  attribute :terms_of_service, :boolean
  validates :terms_of_service, acceptance: { message: "must be accepted to create an account", allow_nil: false }, on: :create, if: :new_record_from_sign_up?
  before_create { self.terms_accepted_at ||= Time.current if terms_of_service }

  # Relationships
  has_many :business_users, dependent: :destroy
  has_many :businesses, through: :business_users
  has_many :owned_businesses, class_name: "Business", foreign_key: "owner_id", dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :first_name, presence: true, if: :new_record_from_sign_up?
  validates :first_name, :last_name, length: { maximum: 100 }

  attr_accessor :new_record_from_sign_up
  alias new_record_from_sign_up? new_record_from_sign_up

  # Instance methods

  # Devise stores this in the session and the remember-me cookie. Mixing in session_token means
  # rotating it signs the user out everywhere (sign_out_everywhere!).
  def authenticatable_salt
    "#{super}#{session_token}"
  end

  def sign_out_everywhere!
    update_columns(session_token: SecureRandom.base58(24), remember_created_at: nil)
  end

  # Unconfirmed users can work but not send to clients (ACC-01).
  def can_send_to_clients? = confirmed?
  def full_name
    return email if first_name.blank? && last_name.blank?
    [ first_name, last_name ].compact.join(" ")
  end

  def has_business?
    business_users.active.any?
  end

  def is_business_owner?
    owned_businesses.any? || business_users.owners.any?
  end

  def owner_of?(business)
    business_users.where(business: business, role: "owner").exists? ||
      owned_businesses.include?(business)
  end

  def member_of?(business)
    business_users.where(business: business).active.exists?
  end

  def role_in(business)
    business_users.find_by(business: business)&.role
  end
end
