class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Business relationships
  belongs_to :business, optional: true
  has_many :owned_businesses, class_name: 'Business', foreign_key: 'owner_id', dependent: :destroy

  # Business management methods
  def has_business?
    business.present?
  end

  def current_business
    business
  end
end
