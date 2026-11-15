# One optional level of grouping for catalog items (CAT-03).
class CatalogCategory < ApplicationRecord
  include BusinessOwned

  has_many :items, class_name: "CatalogItem", foreign_key: :category_id, inverse_of: :category, dependent: :nullify

  normalizes :name, with: ->(name) { name.to_s.squish }
  validates :name, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: :business_id, case_sensitive: false }

  default_scope { order(:position, :name) }
end
