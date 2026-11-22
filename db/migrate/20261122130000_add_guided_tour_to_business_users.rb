# ACC-08: where each member is with the guided tour, per business, for showing it and for
# product measurement (no personal data: a status, the stop's key and two times).
class AddGuidedTourToBusinessUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :business_users, bulk: true do |t|
      t.string :tour_status # offered, started, finished, skipped; nil: never offered (it's in Help)
      t.string :tour_stop # the stop reached, or where it was ended ("offer" when skipped there)
      t.datetime :tour_offered_at
      t.datetime :tour_ended_at
    end
  end
end
