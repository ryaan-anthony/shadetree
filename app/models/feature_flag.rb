# The stored state of one release flag. Use Feature, not this model, to check or change flags.
class FeatureFlag < ApplicationRecord
  STATES = %w[off on businesses percentage].freeze

  validates :name, presence: true, uniqueness: true
  validates :state, inclusion: { in: STATES }
  validates :percentage, numericality: { only_integer: true, in: 0..100 }

  after_commit { Rails.cache.delete(Feature.cache_key(name)) }

  def enabled_for?(business)
    case state
    when "on" then true
    when "businesses" then business.present? && business_ids.include?(business.id)
    when "percentage" then business.present? && Feature.bucket(name, business) < percentage
    else false
    end
  end
end
