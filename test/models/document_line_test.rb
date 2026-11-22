require "test_helper"

# Lines say their unit for the quantity (QA #274): "2 visits", but typed units stay as typed.
class DocumentLineTest < ActiveSupport::TestCase
  def line(quantity, unit) = as_business(businesses(:one)) { QuoteLineItem.new(quantity:, unit:) }

  test "the catalog's own units are plural for any quantity but one" do
    assert_equal "1 visit", line(1, "visit").quantity_label
    assert_equal "2 visits", line(2, "visit").quantity_label
    assert_equal "1.5 hours", line("1.5", "hour").quantity_label
    assert_equal "0.5 hours", line("0.5", "hour").quantity_label
  end

  test "other units, and lines without one, are left alone" do
    assert_equal "3 each", line(3, "each").quantity_label
    assert_equal "6 cu yd", line(6, "cu yd").quantity_label
    assert_equal "120 sq ft", line(120, "sq ft").quantity_label
    assert_equal "3", line(3, nil).quantity_label
  end
end
