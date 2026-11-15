# Industry presets (CAT-05). Operators can change presets without a deploy:
#   bin/rails presets:sync                 # add industries missing from the database
#   bin/rails presets:sync OVERWRITE=1     # replace every preset with db/seeds/industry_presets.yml
#   bin/rails presets:export > presets.yml # dump what's in the database, edit, then
#   bin/rails presets:import FILE=presets.yml
#   bin/rails presets:list
namespace :presets do
  desc "Load db/seeds/industry_presets.yml (OVERWRITE=1 replaces existing presets)"
  task sync: :environment do
    written = IndustryPreset.sync!(overwrite: ENV["OVERWRITE"] == "1")
    puts written.any? ? "Wrote presets: #{written.join(", ")}" : "Presets already up to date (OVERWRITE=1 to replace)"
  end

  desc "Replace presets from FILE (same format as db/seeds/industry_presets.yml)"
  task import: :environment do
    file = ENV.fetch("FILE") { abort "Usage: bin/rails presets:import FILE=presets.yml" }
    IndustryPreset.transaction { puts "Imported: #{IndustryPreset.sync!(overwrite: true, source: file).join(", ")}" }
  rescue ActiveRecord::RecordInvalid => e
    abort "Not imported: #{e.record.industry}: #{e.record.errors.full_messages.to_sentence}"
  end

  desc "Print the presets in the database as YAML"
  task export: :environment do
    puts IndustryPreset.order(:industry).to_h { [ _1.industry, { "default_visit_minutes" => _1.default_visit_minutes, "items" => _1.items } ] }.to_yaml
  end

  desc "List presets"
  task list: :environment do
    IndustryPreset.order(:industry).each { puts format("%-18s %2d items, %3d min visits", _1.industry, _1.items.size, _1.default_visit_minutes) }
    missing = Industry.keys - IndustryPreset.pluck(:industry)
    puts "No preset: #{missing.join(", ")}" if missing.any?
  end
end
