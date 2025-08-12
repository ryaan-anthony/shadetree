# Primary business entity containing core company information.
#
# The Business model represents a company or organization that provides services
# through the Shadetree platform. Each business has an owner (User) and can have
# multiple users and locations associated with it.
#
# @attr [String] name Business name (required)
# @attr [String] timezone Business timezone
# @attr [String] email Primary business email (required)
# @attr [String] phone Primary business phone
# @attr [String] website Business website URL
# @attr [String] currency Business currency (default: 'USD')
# @attr [String] brand_color Primary brand color (default: '#059669')
# @attr [String] logo_url Business logo URL
# @attr [Boolean] active Business status (default: true)
# @attr [Integer] owner_id Business owner (foreign key to users)
class Business < ApplicationRecord
  # Relationships
  belongs_to :owner, class_name: 'User'
  has_many :users, dependent: :nullify
  has_many :locations, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :owner_id, presence: true
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true
  validates :currency, inclusion: { in: %w[USD EUR GBP CAD AUD] }, allow_blank: true

  # Scopes
  scope :active, -> { where(active: true) }

  # Callbacks
  before_save :set_default_brand_color

  # Instance methods
  def complete_setup?
    name.present? && email.present? && phone.present?
  end

  private

  def set_default_brand_color
    self.brand_color = '#059669' if brand_color.blank?
  end
end
