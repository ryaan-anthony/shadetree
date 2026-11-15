# Starter services for an industry (CAT-05): what a new business can add to its catalog in
# one step, plus the industry's default visit length. Global reference data, not owned by a
# business. db/seeds/industry_presets.yml is the starting content; operators can change rows
# in the database without a deploy (see lib/tasks/presets.rake).
class IndustryPreset < ApplicationRecord
  SOURCE = Rails.root.join("db/seeds/industry_presets.yml")
  ITEM_KEYS = %w[name description unit custom_unit taxable duration_minutes category].freeze
  TEXT_KEYS = %w[name description unit custom_unit category].freeze
  PRESET_KEYS = %w[default_visit_minutes items].freeze

  # A preset file that isn't shaped like db/seeds/industry_presets.yml.
  class FileError < StandardError; end

  # One starter service. `taxable` defaults to true, like a new catalog item.
  Item = Data.define(*ITEM_KEYS.map(&:to_sym)) do
    def self.from(hash)
      hash = hash.to_h.stringify_keys.slice(*ITEM_KEYS)
      new(**ITEM_KEYS.index_with { nil }.merge(hash).merge("taxable" => hash.fetch("taxable", true)).symbolize_keys)
    end

    def key = self.class.key(name)
    def category_key = category.present? ? self.class.key(category) : nil
    def self.key(text) = text.to_s.squish.downcase

    def catalog_attributes
      { name:, description:, unit: unit.presence || "each", custom_unit:, taxable:, duration_minutes: }
    end
  end

  validates :industry, presence: true, uniqueness: true, inclusion: { in: -> { Industry.keys } }
  validates :default_visit_minutes, numericality: { only_integer: true, in: 5..(24 * 60) }
  validate :items_are_valid

  def self.for(industry) = find_by(industry: industry.to_s)

  # Loads the YAML file. Industries already in the database are left alone unless
  # overwrite: true, so operator edits survive deploys. Returns the industries written.
  # Raises FileError for a malformed file and RecordInvalid for invalid content.
  def self.sync!(overwrite: false, source: SOURCE)
    read_file(source).filter_map do |industry, data|
      preset = find_or_initialize_by(industry:)
      next if preset.persisted? && !overwrite

      preset.update!(default_visit_minutes: data.fetch("default_visit_minutes", 60), items: data.fetch("items", []))
      industry
    end
  end

  def self.read_file(source)
    data = YAML.safe_load_file(source)
    raise FileError, "#{source} should map industry keys to presets" unless data.is_a?(Hash)

    data.each do |industry, preset|
      raise FileError, "#{industry}: expected default_visit_minutes and items" unless preset.is_a?(Hash)

      unknown = preset.keys - PRESET_KEYS
      raise FileError, "#{industry}: unknown keys #{unknown.join(", ")} (allowed: #{PRESET_KEYS.join(", ")})" if unknown.any?
      raise FileError, "#{industry}: items should be a list" unless preset.fetch("items", []).is_a?(Array)
    end
  rescue Psych::Exception => e
    raise FileError, "#{source} isn't valid YAML: #{e.message}"
  end

  def name = Industry.name_for(industry)
  def item_list = items.map { Item.from(_1) }

  # Each starter item paired with the current business's existing catalog item of the same
  # name (case-insensitive, archived included), or nil when it isn't in the catalog yet.
  def with_existing
    existing = CatalogItem.pluck(:name, :archived_at).to_h { |name, archived_at| [ name.squish.downcase, archived_at ? :archived : :active ] }
    item_list.map { [ _1, existing[_1.key] ] }
  end

  # Adds the chosen starter items (by name) to the current business's catalog, skipping any
  # it already has, so adding a preset twice never duplicates. Categories are matched by name
  # or created. Returns the catalog items created.
  def add_to_catalog!(names)
    wanted = Array(names).map { _1.to_s.squish.downcase }.to_set
    CatalogItem.transaction do
      # Serialize concurrent adds for one business so the name check below can't race.
      Business.where(id: Current.business.id).lock.pluck(:id)
      present = CatalogItem.pluck(:name).to_set { Item.key(_1) }
      categories = CatalogCategory.all.index_by { Item.key(_1.name) }

      item_list.select { wanted.include?(_1.key) && !present.include?(_1.key) }.map do |item|
        category = item.category_key && (categories[item.category_key] ||= CatalogCategory.create!(name: item.category))
        CatalogItem.create!(item.catalog_attributes.merge(category:))
      end
    end
  end

  private

  def items_are_valid
    return errors.add(:items, "must be a list") unless items.is_a?(Array)

    names = []
    items.each_with_index do |raw, index|
      unless raw.is_a?(Hash) && (raw.keys - ITEM_KEYS).empty?
        errors.add(:items, "item #{index + 1} has unknown fields (allowed: #{ITEM_KEYS.join(", ")})")
        next
      end
      item = Item.from(raw)
      problems = item_problems(item)
      errors.add(:items, "item #{index + 1} (#{item.name.presence || "unnamed"}): #{problems.to_sentence}") if problems.any?
      errors.add(:items, "item #{index + 1} repeats #{item.name}") if names.include?(item.key)
      names << item.key
    end
  end

  # The same rules as CatalogItem, checked here because presets have no business to build
  # a catalog item in.
  def item_problems(item)
    unit = item.unit.presence || "each"
    wrong_type = TEXT_KEYS.select { (value = item.public_send(_1)) && !value.is_a?(String) }
    return wrong_type.map { "#{_1} must be text" } if wrong_type.any?

    [
      ("name is missing" if item.name.to_s.squish.empty?),
      ("name is longer than 120 characters" if item.name.to_s.length > 120),
      ("description is longer than 2000 characters" if item.description.to_s.length > 2_000),
      ("unit must be one of #{CatalogItem::UNITS.keys.join(", ")}" unless CatalogItem::UNITS.key?(unit)),
      ("custom_unit is needed (up to 20 characters) when unit is custom" if unit == "custom" && !item.custom_unit.to_s.strip.length.between?(1, 20)),
      ("duration_minutes must be a whole number from 1 to 1440" unless item.duration_minutes.nil? || (item.duration_minutes.is_a?(Integer) && item.duration_minutes.between?(1, 1440))),
      ("taxable must be true or false" unless [ true, false ].include?(item.taxable)),
      ("category is longer than 60 characters" if item.category.to_s.length > 60)
    ].compact
  end
end
