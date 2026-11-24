# OPS-06: the database bin/help-screenshots wipes and fills with the demo data. It's the
# database DATABASE_URL names with "_help" added to the name itself (never to anything after
# it, such as ?application_name=…), or HELP_DATABASE_URL as given when its database's name ends
# in "_help". Anything else is refused before anything is dropped. Plain Ruby: the script asks
# for it before Rails boots.
#
#   ruby lib/help_screenshots_database.rb   # prints the URL, or explains and exits 1
require "uri"

module HelpScreenshotsDatabase
  class Refused < StandardError; end

  SUFFIX = "_help"
  DEFAULT = "postgres:///shadetree_test"
  NAME = /\A[A-Za-z0-9_.-]+\z/

  def self.url(database_url: ENV["DATABASE_URL"], help_url: ENV["HELP_DATABASE_URL"])
    if help_url.to_s.strip != ""
      name = database_name(parse(help_url))
      raise Refused, "HELP_DATABASE_URL names #{name.inspect}, which doesn't end in #{SUFFIX}" unless name.end_with?(SUFFIX)

      return help_url
    end
    uri = parse(database_url.to_s.strip == "" ? DEFAULT : database_url)
    uri.path = "/#{database_name(uri)}#{SUFFIX}"
    uri.to_s
  end

  def self.parse(url)
    uri = URI.parse(url)
    raise Refused, "#{uri.scheme.inspect} isn't a PostgreSQL URL" unless %w[postgres postgresql].include?(uri.scheme)

    uri
  rescue URI::InvalidURIError
    raise Refused, "that isn't a database URL"
  end

  def self.database_name(uri)
    name = URI.decode_www_form_component(uri.path.to_s.delete_prefix("/"))
    raise Refused, "the URL doesn't name a database (postgres:///name)" unless name.match?(NAME)

    name
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
