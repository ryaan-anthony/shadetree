# A plan businesses can be on (BIL-01): its prices, limits and features, as data operators edit
# without a deploy (bin/rails plans:set, then the operator console). Platform-wide, not owned by
# a business. Ask what a business may do through Entitlements, never the plan directly.
class Plan < ApplicationRecord
  SOURCE = Rails.root.join("db/seeds/plans.yml")

  # Every limit and feature the app knows, with the words for the plan page. A key a plan
  # doesn't list is unlimited (limits) or off (features).
  LIMITS = {
    "quotes_sent" => "Quotes sent a month",
    "team_members" => "Team members",
    "active_automations" => "Active automations" # NTF-04
  }.freeze
  FEATURES = {
    "remove_powered_by" => "No “Powered by Shadetree” on client pages and emails",
    "message_templates" => "Editable message templates",
    "automations" => "Automations",
    "custom_roles" => "Custom roles",
    "locations" => "More than one location",
    "sms" => "Text messages",
    "priority_support" => "Priority support"
  }.freeze

  has_many :businesses, dependent: :restrict_with_exception

  validates :key, presence: true, uniqueness: true, format: { with: /\A[a-z0-9_]+\z/ }
  validates :name, presence: true
  validates :monthly_price_cents, :annual_price_cents, numericality: { greater_than_or_equal_to: 0 }
  validate :known_keys

  scope :listed, -> { where(public: true).order(:position, :id) }
  scope :free, -> { where(monthly_price_cents: 0, annual_price_cents: 0) }

  validates :default, uniqueness: { message: "is already another plan" }, if: :default

  def self.default! = find_by!(default: true)

  def monthly_price = Money.new(monthly_price_cents, currency)
  def annual_price = Money.new(annual_price_cents, currency)
  def free? = monthly_price_cents.zero? && annual_price_cents.zero?

  # Adds the plans in db/seeds/plans.yml that don't exist yet; existing plans keep their edits
  # unless overwrite: true. Returns the keys it wrote.
  def self.sync!(overwrite: false, source: SOURCE)
    YAML.safe_load_file(source).filter_map do |key, data|
      plan = find_or_initialize_by(key:)
      next if plan.persisted? && !overwrite

      plan.update!(name: data.fetch("name"), description: data["description"], public: data.fetch("public", true),
                   default: data.fetch("default", false), position: data.fetch("position", 0),
                   monthly_price_cents: Money.parse(data.fetch("monthly_price", "0"), plan.currency).cents,
                   annual_price_cents: Money.parse(data.fetch("annual_price", "0"), plan.currency).cents,
                   limits: data.fetch("limits", {}), features: data.fetch("features", {}))
      key
    end
  end

  private

  def known_keys
    self.class.override_problems({ "limits" => limits, "features" => features }).each do |problem|
      errors.add(problem.start_with?("limits") ? :limits : :features, problem.sub(/\A(limits|features) /, ""))
    end
  end

  # What's wrong with a set of limits and features (a plan's, or a business's overrides).
  def self.override_problems(set)
    set = set.to_h
    problems = []
    unknown = set.keys - %w[limits features]
    problems << "#{unknown.join(", ")} can't be overridden" if unknown.any?
    limits, features = set.fetch("limits", {}).to_h, set.fetch("features", {}).to_h
    problems << "limits has unknown keys: #{(limits.keys - LIMITS.keys).join(", ")}" if (limits.keys - LIMITS.keys).any?
    problems << "limits must be whole numbers or empty (unlimited)" unless limits.values.all? { _1.nil? || (_1.is_a?(Integer) && _1 >= 0) }
    problems << "features has unknown keys: #{(features.keys - FEATURES.keys).join(", ")}" if (features.keys - FEATURES.keys).any?
    problems << "features must be true or false" unless features.values.all? { _1 == true || _1 == false }
    problems
  end
end
