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
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Relationships
  belongs_to :business, optional: true
  has_many :owned_businesses, class_name: 'Business', foreign_key: 'owner_id', dependent: :destroy
  has_one :staff_member, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :first_name, presence: true, allow_blank: true
  validates :last_name, presence: true, allow_blank: true

  # Instance methods
  def full_name
    return email if first_name.blank? && last_name.blank?
    [first_name, last_name].compact.join(' ')
  end

  def has_business?
    business.present?
  end

  def current_business
    business
  end

  def is_business_owner?
    owned_businesses.any?
  end

  def is_staff_member?
    staff_member.present?
  end
end
