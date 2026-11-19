# BIL-02: usage periods. Free plans count the calendar month in the business's time zone; a paid
# plan counts its billing cycle, which starts on the subscription's anchor (BIL-04 sets it).
class AddUsagePeriodAnchorToBusinesses < ActiveRecord::Migration[8.1]
  def change
    add_column :businesses, :billing_cycle_anchor, :datetime
  end
end
