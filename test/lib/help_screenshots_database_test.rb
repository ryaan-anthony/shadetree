require "test_helper"
require Rails.root.join("lib/help_screenshots_database")

# OPS-06: bin/help-screenshots wipes the database this names, so the "_help" suffix goes on the
# database's own name, query parameters and all, and anything else is refused before a drop.
class HelpScreenshotsDatabaseTest < ActiveSupport::TestCase
  def url(database_url, help_url = nil) = HelpScreenshotsDatabase.url(database_url:, help_url:)

  test "adds _help to the database's name, keeping the rest of the URL" do
    assert_equal "postgres:///shadetree_test_help", url(nil)
    assert_equal "postgres:///shadetree_test_help", url("")
    assert_equal "postgres://postgres:postgres@localhost:5432/shadetree_test_help", url("postgres://postgres:postgres@localhost:5432/shadetree_test")
    assert_equal "postgres:///x_help?application_name=dev", url("postgres:///x?application_name=dev")
    assert_equal "postgresql://h/x_help?sslmode=disable&application_name=a", url("postgresql://h/x?sslmode=disable&application_name=a")
  end

  test "HELP_DATABASE_URL is used as given only when its database ends in _help" do
    assert_equal "postgres:///mine_help?application_name=dev", url("postgres:///x", "postgres:///mine_help?application_name=dev")
    assert_raises(HelpScreenshotsDatabase::Refused) { url(nil, "postgres:///x?application_name=dev_help") }
    assert_raises(HelpScreenshotsDatabase::Refused) { url(nil, "postgres:///production") }
  end

  test "refuses a query string that names another database, which Rails would use instead" do
    error = assert_raises(HelpScreenshotsDatabase::Refused) { url("postgres:///x?database=junk2") }
    assert_includes error.message, "database"
    assert_raises(HelpScreenshotsDatabase::Refused) { url("postgres:///x?application_name=a&dbname=junk2") }
    assert_raises(HelpScreenshotsDatabase::Refused) { url(nil, "postgres:///mine_help?database=junk2") }
    assert_raises(HelpScreenshotsDatabase::Refused) { url(nil, "postgres:///mine_help?dbname=production") }
  end

  test "checks the name Rails resolves, not just the path" do
    assert_equal "shadetree_test_help", ActiveRecord::DatabaseConfigurations::UrlConfig.new("test", "primary", url(nil), {}).database
    assert_equal "x_help", ActiveRecord::DatabaseConfigurations::UrlConfig.new("test", "primary", url("postgres:///x?application_name=dev"), {}).database
  end

  test "refuses what isn't a PostgreSQL URL naming a database" do
    [ "mysql://h/x", "postgres://host/", "postgres:///", "not a url at all", "postgres:///a;drop" ].each do |bad|
      assert_raises(HelpScreenshotsDatabase::Refused, bad) { url(bad) }
    end
  end
end
