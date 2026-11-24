# OPS-06: tests that need particular articles read them from test/fixtures/files/help, a small
# library with an article for each topic, instead of the real content/help.
#
#   class SomeTest < ActionDispatch::IntegrationTest
#     include HelpLibraryHelpers   # every test here uses the fixture library
module HelpLibraryHelpers
  FIXTURES = Rails.root.join("test/fixtures/files/help")

  def self.included(base)
    base.setup { use_help_library(FIXTURES) }
    base.teardown { use_help_library(Rails.root.join("content/help")) }
  end

  def use_help_library(root)
    HelpCentre.root = root
    HelpCentre.reset!
  end
end
