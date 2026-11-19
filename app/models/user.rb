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

  # Relationships. Accounts aren't destroyed (delete_account! anonymizes them), so these
  # dependents only matter for a user removed outright, e.g. in the console.
  has_many :owned_businesses, class_name: "Business", foreign_key: "owner_id", dependent: :destroy
  has_many :business_users, dependent: :destroy
  has_many :user_sessions, dependent: :delete_all
  has_many :businesses, through: :business_users

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :first_name, presence: true, if: :new_record_from_sign_up?
  validates :first_name, :last_name, length: { maximum: 100 }

  attr_accessor :new_record_from_sign_up
  alias new_record_from_sign_up? new_record_from_sign_up

  # Instance methods

  # Account deletion (ACC-06) -------------------------------------------------------------------

  FORMER_MEMBER = "Former member"
  DELETED_EMAIL_DOMAIN = "deleted.invalid"
  # A business with any of these is someone's work, so its only Owner can't just walk away.
  BUSINESS_RECORDS = %w[Client ServiceRequest Quote Job Invoice].freeze

  def deleted? = deleted_at.present?

  # A deleted account can't sign in (Devise asks this on every request).
  def active_for_authentication? = super && !deleted?

  # Businesses this person is the only active Owner of, that others depend on: other active
  # members, or any clients, requests, quotes, jobs or invoices. Deletion waits until another
  # member is made an Owner (or Shadetree closes the business).
  def businesses_blocking_deletion
    sole_owner_memberships.filter_map { |membership| membership.business if business_in_use?(membership.business) }
  end

  # Removes everything personal and ends every membership; the row stays so records it made
  # still point somewhere ("Former member"). Empty businesses it alone owned are closed.
  # Returns false (deleting nothing) if a business blocks it.
  def delete_account!
    transaction do
      lock!
      return false if businesses_blocking_deletion.any?

      sole_owner_memberships.each { |membership| membership.business.update_columns(active: false, updated_at: Time.current) }
      business_users.active.update_all(active: false, deactivated_at: Time.current, updated_at: Time.current)
      user_sessions.delete_all
      Tenancy.across_businesses(reason: "deleting an account's notifications") { Notification.where(user_id: id).delete_all }
      update_columns(email: "deleted-user-#{id}@#{DELETED_EMAIL_DOMAIN}", unconfirmed_email: nil, first_name: nil, last_name: nil,
                     encrypted_password: Devise::Encryptor.digest(self.class, SecureRandom.base58(32)), session_token: SecureRandom.base58(24),
                     reset_password_token: nil, reset_password_sent_at: nil, confirmation_token: nil, unlock_token: nil, locked_at: nil,
                     remember_created_at: nil, last_business_id: nil, deleted_at: Time.current, updated_at: Time.current)
    end
    true
  end

  # Devise stores this in the session and the remember-me cookie. Mixing in session_token means
  # rotating it signs the user out everywhere (sign_out_everywhere!).
  def authenticatable_salt
    "#{super}#{session_token}"
  end

  # Ends every other browser's session (ACC-06 lists them); `except` is the one to keep.
  def sign_out_everywhere!(except: nil)
    user_sessions.active.where.not(id: except&.id).update_all(revoked_at: Time.current)
    update_columns(session_token: SecureRandom.base58(24), remember_created_at: nil)
  end

  # Unconfirmed users can work but not send to clients (ACC-01).
  # Devise's emails go out in the background (NTF-01): a slow mail server can't stall sign-up.
  def send_devise_notification(notification, *)
    devise_mailer.send(notification, self, *).deliver_later
  end

  def can_send_to_clients? = confirmed?
  def full_name
    return FORMER_MEMBER if deleted?
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

  private

  def sole_owner_memberships
    business_users.active.owners.includes(:business).select { |membership| membership.last_active_owner? }
  end

  def business_in_use?(business)
    return true if business.business_users.active.where.not(user_id: id).exists?

    Tenancy.with_business(business) { BUSINESS_RECORDS.any? { |name| name.constantize.exists? } }
  end
end
