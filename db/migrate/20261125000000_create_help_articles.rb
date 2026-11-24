# OPS-06: the help articles, loaded from content/help/articles at boot (HelpArticle.sync!) and
# searched with PostgreSQL full-text search, the title weighted above the summary and the text.
class CreateHelpArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :help_articles do |t|
      t.string :slug, null: false, index: { unique: true }
      t.string :title, null: false
      t.string :summary, null: false
      t.string :category, null: false
      t.string :topics, array: true, null: false, default: []
      t.text :body, null: false
      t.string :digest, null: false # of the file, so a sync rewrites only what changed
      t.virtual :searchable, type: :tsvector, stored: true, as: <<~SQL.squish
        setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(summary, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(body, '')), 'C')
      SQL
      t.timestamps
    end
    add_index :help_articles, :searchable, using: :gin
    add_index :help_articles, :category
  end
end
