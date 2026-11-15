# The industries a business can choose (config/industries.yml), shared by setup, settings and
# industry presets (CAT-05).
class Industry
  Entry = Data.define(:key, :name, :data)

  def self.all
    @all ||= YAML.safe_load_file(Rails.root.join("config/industries.yml")).map do |key, data|
      Entry.new(key:, name: data.fetch("name"), data: data.except("name").freeze)
    end.freeze
  end

  def self.keys = all.map(&:key)
  def self.find(key) = all.find { _1.key == key.to_s }
  def self.name_for(key) = find(key)&.name
  def self.options = all.map { [ _1.name, _1.key ] }
end
