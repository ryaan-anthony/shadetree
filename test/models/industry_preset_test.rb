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
