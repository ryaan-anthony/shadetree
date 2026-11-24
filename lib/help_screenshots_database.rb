# OPS-06: the database bin/help-screenshots wipes and fills with the demo data. It's the database
# DATABASE_URL names with "_help" added to its name, or HELP_DATABASE_URL as given. Before
# anything is dropped, the name is resolved as Rails will resolve it, and refused unless it ends
# in "_help"; a query string that names a database itself (?database=… or ?dbname=…) is refused
# too, since Rails would connect to that one instead. Runs before Rails boots.
#
#   ruby lib/help_screenshots_database.rb   # prints the URL, or explains and exits 1
require "uri"
require "active_record"
require "active_record/database_configurations"

module HelpScreenshotsDatabase
  class Refused < StandardError; end

  SUFFIX = "_help"
  DEFAULT = "postgres:///shadetree_test"
  NAME = /\A[A-Za-z0-9_.-]+\z/
  NAMING_PARAMETERS = %w[database dbname].freeze

  def self.url(database_url: ENV["DATABASE_URL"], help_url: ENV["HELP_DATABASE_URL"])
    url = if help_url.to_s.strip != ""
      help_url
    else
      uri = parse(database_url.to_s.strip == "" ? DEFAULT : database_url)
      name = URI.decode_www_form_component(uri.path.to_s.delete_prefix("/"))
      raise Refused, "the URL doesn't name a database (postgres:///name)" unless name.match?(NAME)

      uri.path = "/#{name}#{SUFFIX}"
      uri.to_s
    end
    check!(url)
    url
  end

  # The database Rails would connect to with this URL, which must end in _help.
  def self.check!(url)
    uri = parse(url)
    named = URI.decode_www_form(uri.query.to_s).map(&:first) & NAMING_PARAMETERS
    raise Refused, "the URL's query names a database (#{named.join(", ")}=…); put the name in the path" if named.any?

    name = ActiveRecord::DatabaseConfigurations::UrlConfig.new("test", "primary", url, {}).database.to_s
    raise Refused, "it would use the database #{name.inspect}, whose name doesn't end in #{SUFFIX}" unless name.match?(NAME) && name.end_with?(SUFFIX)
  end

  def self.parse(url)
    uri = URI.parse(url)
    raise Refused, "#{uri.scheme.inspect} isn't a PostgreSQL URL" unless %w[postgres postgresql].include?(uri.scheme)

    uri
  rescue URI::InvalidURIError, ArgumentError
    raise Refused, "that isn't a database URL"
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    puts HelpScreenshotsDatabase.url
  rescue HelpScreenshotsDatabase::Refused => error
    warn "bin/help-screenshots: #{error.message}. Nothing was dropped."
    exit 1
  end
end
