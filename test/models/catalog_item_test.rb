require "test_helper"

# CAT-03: the service catalog.
class CatalogItemTest < ActiveSupport::TestCase
  setup { @business = businesses(:one) }

  def item(**attributes) = as_business(@business) { CatalogItem.create!(name: "Weekly mow", unit_price: "45", **attributes) }

  test "prices are money in the business currency, and may be blank" do
    as_business(@business) do
      mow = item
      assert_equal Money.new(4500, "USD"), mow.unit_price
      mow.update!(unit_price: "")
      assert_nil mow.reload.unit_price
      bad = CatalogItem.new(name: "Trip fee", unit_price: "abc")
      assert_not bad.valid?
      assert_includes bad.errors[:unit_price], "is not a valid amount"
    end
  end

  test "validates name, unit, custom unit and duration" do
    as_business(@business) do
      item = CatalogItem.new(name: " ", unit: "custom", duration_minutes: 0, unit_price_cents: -1)
      assert_not item.valid?
      assert item.errors.of_kind?(:name, :blank)
      assert item.errors.of_kind?(:custom_unit, :blank)
      assert item.errors.of_kind?(:duration_minutes, :in)
      assert_includes item.errors[:unit_price], "can't be negative"
      assert_not CatalogItem.new(name: "x", unit: "gallon").valid?
    end
  end

  test "unit and duration labels" do
    as_business(@business) do
      assert_equal "sq ft", item(unit: "sq_ft").unit_label
      assert_equal "bag", item(unit: "custom", custom_unit: "bag").unit_label
      assert_equal "1 h 30 min", item(duration_minutes: 90).duration_label
      assert_equal "45 min", item(duration_minutes: 45).duration_label
      assert_nil item.duration_label
    end
  end

  test "archiving hides an item from active and keeps it restorable" do
    as_business(@business) do
      mow = item
      mow.archive!
      assert_not_includes CatalogItem.active, mow
      assert_includes CatalogItem.archived, mow
      mow.restore!
      assert_includes CatalogItem.active, mow
    end
  end

  test "line attributes are a copy, so later edits do not reach existing lines" do
    as_business(@business) do
      mow = item(description: "Front and back", taxable: false)
      line = mow.line_attributes
      mow.update!(name: "Mow", unit_price: "60")
      assert_equal({ "catalog_item_uid" => mow.uid, "name" => "Weekly mow", "description" => "Front and back",
                     "unit" => "each", "unit_price_cents" => 4500, "taxable" => false }, line)
    end
  end

  test "new items go last in their category, and move swaps neighbours" do
    as_business(@business) do
      a, b, c = %w[A B C].map { item(name: _1) }
      assert_equal [ 0, 1, 2 ], [ a, b, c ].map(&:position)
      c.move!(-1)
      assert_equal %w[A C B], CatalogItem.ordered.map(&:name)
      a.move!(-1) # already first
      assert_equal %w[A C B], CatalogItem.ordered.map(&:name)
    end
  end

  test "duplicate makes an unsaved, unarchived copy" do
    as_business(@business) do
      mow = item
      mow.archive!
      copy = mow.duplicate
      assert copy.new_record?
      assert_nil copy.archived_at
      assert_equal "Weekly mow (copy)", copy.name
      copy.save!
      assert_not_equal mow.uid, copy.uid
    end
  end

  test "search matches name or description, case-insensitively, and escapes wildcards" do
    as_business(@business) do
      item(name: "Hedge trim", description: "Shrubs and hedges")
      item(name: "Mulch", description: "Per bag")
      item(name: "100% organic feed")
      assert_equal [ "Hedge trim" ], CatalogItem.search("SHRUB").map(&:name)
      assert_equal [ "Mulch" ], CatalogItem.search("bag").map(&:name)
      assert_equal [ "100% organic feed" ], CatalogItem.search("0%").map(&:name)
      assert_equal 3, CatalogItem.search("").count
    end
  end

  test "items and categories belong to one business" do
    mine = item
    as_business(businesses(:two)) do
      assert_nil CatalogItem.find_by(id: mine.id)
      assert_empty CatalogItem.all
    end
  end

  test "category names are unique per business, ignoring case" do
    as_business(@business) { CatalogCategory.create!(name: "Lawn") }
    as_business(@business) { assert_not CatalogCategory.new(name: "lawn").valid? }
    as_business(businesses(:two)) { assert CatalogCategory.create!(name: "Lawn") }
  end

  test "deleting a category leaves its items uncategorized" do
    as_business(@business) do
      lawn = CatalogCategory.create!(name: "Lawn")
      mow = item(category: lawn)
      lawn.destroy!
      assert_nil mow.reload.category
    end
  end
end
