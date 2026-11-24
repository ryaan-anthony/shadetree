# OPS-06: "Was this helpful?" counts per article (nothing about who), and the words of searches
# that found nothing, per day, kept 90 days (PruneHelpSearchMissesJob).
class AddHelpVotesAndSearchMisses < ActiveRecord::Migration[8.1]
  def change
    add_column :help_articles, :helpful_count, :integer, null: false, default: 0
    add_column :help_articles, :unhelpful_count, :integer, null: false, default: 0

    create_table :help_search_misses do |t|
      t.string :words, null: false, limit: 100
      t.date :searched_on, null: false
      t.integer :count, null: false, default: 1
      t.timestamps
    end
    add_index :help_search_misses, %i[words searched_on], unique: true
    add_index :help_search_misses, :searched_on
  end
end
