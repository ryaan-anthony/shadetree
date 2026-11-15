require "test_helper"

# CAT-05: industry presets.
class IndustryPresetTest < ActiveSupport::TestCase
  setup do
    IndustryPreset.sync!
    @business = businesses(:one)
  end

  test "every industry has a valid preset with starter items" do
    assert_equal Industry.keys.sort, IndustryPreset.pluck(:industry).sort
    IndustryPreset.find_each do |preset|
      assert preset.valid?, "#{preset.industry}: #{preset.errors.full_messages.to_sentence}"
      assert_operator preset.items.size, :>=, 3, preset.industry
    end
  end

  test "sync adds missing presets but keeps operator edits unless overwriting" do
    cleaning = IndustryPreset.for("cleaning")
    cleaning.update!(items: [ { "name" => "Operator special" } ])
    IndustryPreset.for("pest").destroy!

    assert_equal [ "pest" ], IndustryPreset.sync!
    assert_equal [ "Operator special" ], cleaning.reload.item_list.map(&:name)

    IndustryPreset.sync!(overwrite: true)
    assert_includes cleaning.reload.item_list.map(&:name), "Deep clean"
  end

  test "bad items are rejected with a clear message" do
    preset = IndustryPreset.for("other")
    preset.items = [ { "name" => "Mow", "unit" => "acre" }, { "name" => "mow" }, { "name" => "X", "price" => 5 }, "nope" ]
    assert_not preset.valid?
    messages = preset.errors[:items]
    assert_match(/item 1 \(Mow\): unit must be one of each/, messages.join)
    assert_match(/item 2 repeats mow/, messages.join)
    assert_match(/item 3 has unknown fields/, messages.join)
    assert_match(/item 4 has unknown fields/, messages.join)
    assert_not IndustryPreset.new(industry: "astrology", items: []).valid?

    preset.items = [ { "name" => true }, { "name" => "Feed", "category" => 2024 }, { "name" => "Trim", "description" => %w[a b] } ]
    assert_not preset.valid?
    assert_equal [ "item 1 (true): name must be text", "item 2 (Feed): category must be text", "item 3 (Trim): description must be text" ],
                 preset.errors[:items]
  end

  test "malformed preset files are refused with a clear message, and nothing changes" do
    Dir.mktmpdir do |dir|
      { "" => /should map industry keys/, "- cleaning\n" => /should map industry keys/, "cleaning:\n" => /cleaning: expected/,
        "cleaning:\n  default_visit_minute: 90\n" => /unknown keys default_visit_minute/, "cleaning:\n  items: nope\n" => /items should be a list/,
        "a: &x\n  items: []\nb: *x\n" => /isn't valid YAML/ }.each do |content, message|
        path = File.join(dir, "presets.yml")
        File.write(path, content)
        error = assert_raises(IndustryPreset::FileError) { IndustryPreset.sync!(overwrite: true, source: path) }
        assert_match message, error.message
      end
    end
    assert_includes IndustryPreset.for("cleaning").item_list.map(&:name), "Deep clean"
  end

  test "adding items creates catalog items and categories, and never duplicates" do
    preset = IndustryPreset.for("cleaning")
    as_business(@business) do
      CatalogItem.create!(name: "deep CLEAN") # already offered, different case
      added = preset.add_to_catalog!([ "Standard clean", "Deep clean", "Inside oven", "Not in the preset" ])
      assert_equal [ "Standard clean", "Inside oven" ], added.map(&:name)

      standard = CatalogItem.find_by!(name: "Standard clean")
      assert_equal [ "visit", 150, true, nil ], [ standard.unit, standard.duration_minutes, standard.taxable, standard.unit_price ]
      assert_equal "Cleaning", standard.category.name
      assert_equal "Add-ons", CatalogItem.find_by!(name: "Inside oven").category.name

      assert_empty preset.add_to_catalog!([ "Standard clean", "Inside oven" ]), "adding twice adds nothing"
      assert_equal 3, CatalogItem.count
      assert_equal 2, CatalogCategory.count

      laundry = preset.add_to_catalog!([ "Laundry" ]).first
      assert_equal [ "custom", "load", "load" ], [ laundry.unit, laundry.custom_unit, laundry.unit_label ]
    end
  end

  test "categories match ignoring case and extra spaces" do
    preset = IndustryPreset.for("cleaning")
    preset.update!(items: [ { "name" => "Window wash", "category" => "  add-ONS  " } ])
    as_business(@business) do
      addons = CatalogCategory.create!(name: "Add-ons")
      assert_equal addons, preset.add_to_catalog!([ "Window wash" ]).first.category
      assert_equal 1, CatalogCategory.count
    end
  end

  test "an archived catalog item counts as existing" do
    preset = IndustryPreset.for("cleaning")
    as_business(@business) do
      CatalogItem.create!(name: "Standard clean").archive!
      assert_equal :archived, preset.with_existing.to_h.transform_keys(&:name)["Standard clean"]
      assert_empty preset.add_to_catalog!([ "Standard clean" ])
    end
  end

  test "items land in the current business only" do
    as_business(@business) { IndustryPreset.for("pest").add_to_catalog!([ "Rodent control" ]) }
    as_business(businesses(:two)) do
      assert_empty CatalogItem.all
      assert_equal [ "Rodent control" ], IndustryPreset.for("pest").add_to_catalog!([ "Rodent control" ]).map(&:name)
    end
  end

  test "a business's default visit length comes from its industry" do
    @business.update_column(:industry, "painting")
    assert_equal 480, @business.default_visit_minutes
    @business.update_column(:industry, nil)
    assert_equal 60, @business.default_visit_minutes
  end
end
