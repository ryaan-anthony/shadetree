# Primary business entity containing core company information.
#
# The Business model represents a company or organization that provides services
# through the Shadetree platform. Each business has an owner (User) and can have
# multiple users and locations associated with it.
#
# @attr [String] name Business name (required)
# @attr [String] industry Business industry type
# @attr [Text] address Business physical address
# @attr [Text] description Business description
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
  belongs_to :owner, class_name: "User"
  has_many :business_users, dependent: :destroy
  has_many :users, through: :business_users
  has_many :locations, dependent: :destroy

  # Callbacks
  before_save :set_default_brand_color
  after_create :add_owner_to_business_users

  # Validations
  validates :name, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :owner_id, presence: true
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true
  validates :currency, inclusion: { in: %w[USD EUR GBP CAD AUD] }, allow_blank: true
  validates :industry, inclusion: {
    in: %w[landscaping maintenance cleaning hvac plumbing electrical roofing painting pool pest other]
  }, allow_blank: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :by_industry, ->(industry) { where(industry: industry) }

  # Industry display names
  INDUSTRIES = {
    "landscaping" => "Landscaping & Lawn Care",
    "maintenance" => "Home Maintenance & Repair",
    "cleaning" => "Cleaning Services",
    "hvac" => "HVAC Services",
    "plumbing" => "Plumbing Services",
    "electrical" => "Electrical Services",
    "roofing" => "Roofing Services",
    "painting" => "Painting Services",
    "pool" => "Pool & Spa Services",
    "pest" => "Pest Control",
    "other" => "Other Service Business"
  }.freeze

  # Instance methods

  def industry_name
    INDUSTRIES[industry] || industry
  end

  def add_user(user, role: "member")
    business_users.create!(user: user, role: role, active: true)
  end

  def remove_user(user)
    business_users.where(user: user).destroy_all
  end

  def user_role(user)
    business_users.find_by(user: user)&.role
  end

  private

  def set_default_brand_color
    self.brand_color = "#059669" if brand_color.blank?
  end

  def add_owner_to_business_users
    # Automatically add the owner to business_users with owner role
    business_users.create!(user: owner, role: "owner", active: true) unless business_users.exists?(user: owner)
  end
end
