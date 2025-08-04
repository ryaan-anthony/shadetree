class Business < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :users, dependent: :nullify

  validates :name, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :owner_id, presence: true
  validates :brand_color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_blank: true
  validates :service_area_radius, numericality: { greater_than: 0 }, allow_blank: true

  scope :active, -> { where(active: true) }

  # Set default brand color if not provided
  before_save :set_default_brand_color

  def display_industry
    case industry
    when 'landscaping' then 'Landscaping & Lawn Care'
    when 'maintenance' then 'Home Maintenance & Repair'
    when 'cleaning' then 'Cleaning Services'
    when 'hvac' then 'HVAC'
    when 'plumbing' then 'Plumbing'
    when 'electrical' then 'Electrical'
    when 'painting' then 'Painting'
    else industry&.humanize
    end
  end

  def complete_setup?
    name.present? && email.present? && phone.present? && address.present?
  end

  private

  def set_default_brand_color
    self.brand_color = '#059669' if brand_color.blank?
  end
end
