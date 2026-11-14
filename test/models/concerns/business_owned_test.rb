require "test_helper"

class BusinessOwnedTest < ActiveSupport::TestCase
  class Widget < ApplicationRecord
    self.table_name = "tenancy_widgets"
    include BusinessOwned
    belongs_to_business_record :parent, class_name: "BusinessOwnedTest::Widget", optional: true
  end

  setup do
    ActiveRecord::Base.connection.create_table :tenancy_widgets, temporary: true do |t|
      t.references :business, null: false
      t.references :parent
      t.string :uid, null: false
      t.string :name
    end
    Widget.reset_column_information
    @one, @two = businesses(:one), businesses(:two)
    @mine = as_business(@one) { Widget.create!(name: "mine") }
    @theirs = as_business(@two) { Widget.create!(name: "theirs") }
  end

  test "queries only see the current business" do
    as_business(@one) do
      assert_equal [ "mine" ], Widget.pluck(:name)
      assert_raises(ActiveRecord::RecordNotFound) { Widget.find(@theirs.id) }
      assert_raises(ActiveRecord::RecordNotFound) { Widget.find_by_param!(@theirs.uid) }
      assert_equal @mine, Widget.find_by_param!(@mine.uid)
    end
  end

  test "fails closed with no current business" do
    error = assert_raises(Tenancy::NoBusinessError) { Widget.count }
    assert_match "Tenancy.across_businesses", error.message
  end

  test "the escape hatch is explicit, needs a reason and doesn't leak" do
    assert_raises(ArgumentError) { Tenancy.across_businesses(reason: "") { Widget.count } }
    assert_equal 2, Tenancy.across_businesses(reason: "test") { Widget.count }
    assert_raises(Tenancy::NoBusinessError) { Widget.count }
  end

  test "new records take the current business and can't be created in another" do
    as_business(@one) do
      assert_equal @one, Widget.create!(name: "new").business
      stray = Widget.new(name: "stray", business: @two)
      assert_not stray.valid?
      assert_includes stray.errors[:business], "doesn't match the current business"
    end
  end

  test "records referenced by id must be in the same business" do
    as_business(@one) do
      child = Widget.new(name: "child", parent_id: @theirs.id)
      assert_nil child.parent # the scoped lookup can't load it
      child.parent = Tenancy.across_businesses(reason: "test") { Widget.find(@theirs.id) }
      assert_not child.valid?
      assert_includes child.errors[:parent], "isn't available"
    end
  end

  test "urls use an opaque uid and the business can't be reassigned" do
    assert_equal BusinessOwned::UID_LENGTH, @mine.uid.length
    assert_equal @mine.uid, @mine.to_param
    assert_includes Widget.readonly_attributes, "business_id"
  end

  test "client links resolve across businesses, then act as the record's business" do
    controller = Class.new { include ClientLinkContext; public :find_by_client_link! }.new
    ActiveRecord::Base.connection.add_column :tenancy_widgets, :public_token, :string
    Widget.reset_column_information
    Tenancy.across_businesses(reason: "test") { Widget.where(id: @theirs.id).update_all(public_token: "secret-token") }

    assert_equal @theirs, controller.find_by_client_link!(Widget, "secret-token")
    assert_equal @two, Current.business
    assert_raises(ActiveRecord::RecordNotFound) { controller.find_by_client_link!(Widget, "guess") }
  end
end
