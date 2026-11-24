require "test_helper"

# OPS-06: the CI checks that keep the help articles in step with the app: declared topics,
# links and images, screenshots shown and captured, reviews after captures, and the screen
# digests (with what changes between runs taken out).
class HelpChecksTest < ActiveSupport::TestCase
  include HelpLibraryHelpers

  test "the repo's help articles pass every check" do
    use_help_library(Rails.root.join("content/help"))
    problems = HelpCentre::Checks.problems
    assert_empty problems, problems.join("\n")
  end

  test "pages' help topics are found, tips included, and must be declared" do
    used = HelpCentre::Checks.topics_used
    assert_includes used, [ "send", "app/views/admin/quote_sends/new.html.erb" ]
    assert_includes used.map(&:first), "quote_builder", "each first-time tip's topic"
    topics = HelpCentre.topics.except("send")
    HelpCentre.instance_variable_set(:@topics, topics)
    problems = HelpCentre::Checks.undeclared_topics(HelpCentre.library)
    assert problems.any? { _1.start_with?("app/views/admin/quote_sends/new.html.erb uses the help topic \"send\"") }, problems.inspect
    assert problems.any? { _1.start_with?("send-a-quote: lists the help topic \"send\"") }, problems.inspect
  ensure
    HelpCentre.reset!
  end

  test "every declared topic needs an article" do
    assert_empty HelpCentre::Checks.uncovered_topics(HelpCentre.library)
    HelpCentre.instance_variable_set(:@topics, HelpCentre.topics.merge("widgets" => []))
    assert_equal [ "The help topic \"widgets\" has no article: write one that lists it under topics" ], HelpCentre::Checks.uncovered_topics(HelpCentre.library)
  ensure
    HelpCentre.reset!
  end

  test "links to missing articles, images outside the folder, unshown and uncaptured screenshots, and leftovers fail" do
    dir = Pathname(Dir.mktmpdir).tap { _1.join("articles").mkpath }
    FileUtils.cp(HelpLibraryHelpers::FIXTURES.join("topics.yml"), dir)
    dir.join("articles/one.md").write(<<~MD)
      ---
      title: One
      summary: The first.
      category: quotes
      topics: [send]
      reviewed: 2026-11-20
      screenshots:
        - name: zz-shown
          path: /admin
        - name: zz-unshown
          path: /admin/quotes
      ---
      See [two](two) and [gone](gone). ![Press it](zz-shown) ![Outside](https://example.com/x.png)
    MD
    HelpCentre.image_root = dir.join("images").tap(&:mkpath) # not the real folder: tests run in parallel
    HelpCentre.image_root.join("zz-leftover-1280.webp").write("x")
    dir.join("screenshots.yml").write({ "zz-shown" => { "digest" => "a", "captured_on" => "2026-11-21" } }.to_yaml)
    use_help_library(dir)
    problems = HelpCentre::Checks.problems.join("\n")
    [ "one: links to \"two\", which isn't an article", "one: links to \"gone\"", "zz-shown hasn't been captured",
      "an image from outside the help image folder", "one: declares the screenshot zz-unshown but doesn't show it",
      "app/assets/images/help/zz-leftover-1280.webp isn't used by any article",
      "one: its screenshots were captured on 2026-11-21; re-read it" ].each { assert_includes problems, _1 }
  ensure
    HelpCentre.image_root = Rails.root.join("app/assets/images/help")
    FileUtils.rm_rf(dir) if dir
  end

  test "articles never name another company's product" do
    dir = Pathname(Dir.mktmpdir).tap { _1.join("articles").mkpath }
    FileUtils.cp(HelpLibraryHelpers::FIXTURES.join("topics.yml"), dir)
    dir.join("articles/pay.md").write("---\ntitle: Get paid by card\nsummary: Online.\ncategory: invoices-payments\ntopics: []\nreviewed: 2026-11-24\n---\n" \
                                      "Connect your Stripe account.\n\n![Press Pay with Apple Pay](x.webp)\n")
    dir.join("articles/trees.md").write("---\ntitle: Prune apple trees\nsummary: An outlook for spring.\ncategory: services-prices\ntopics: []\nreviewed: 2026-11-24\n---\n" \
                                        "Polish the chrome trim, then excel at edging.\n")
    use_help_library(dir)
    assert_equal [ "pay: names Stripe; say what it does instead", "pay: names Apple Pay; say what it does instead" ], HelpCentre::Checks.brands(HelpCentre.library)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  test "a screen's digest ignores what changes between runs, and nothing else" do
    shots = HelpCentre::Screenshots
    page = ->(token, uid, extra = "") do
      <<~HTML
        <main><h1>Quote Q-0001</h1><a href="/c/#{token}">Open</a><a href="/admin/quotes/#{uid}">Quote</a>
        <img src="/assets/help/x-1a2b3c4d.webp"><div id="menu-#{SecureRandom.hex(6)}" nonce="#{SecureRandom.hex(8)}"></div>
        <input type="hidden" name="authenticity_token" value="#{SecureRandom.base64(32)}">
        <p>Sent Nov 18, 2026 at 9:05 am · 2026-11-18T14:05:00Z</p>#{extra}</main>
      HTML
    end
    first = shots.digest(page.(SecureRandom.base58(32), SecureRandom.base58(12)), "main")
    assert_equal first, shots.digest(page.(SecureRandom.base58(32), SecureRandom.base58(12)), "main")
    assert_not_equal first, shots.digest(page.(SecureRandom.base58(32), SecureRandom.base58(12), "<button>Send quote</button>"), "main")
    assert_raises(ArgumentError) { shots.digest("<p>no main</p>", "main") }
  end

  test "stale screenshots name what's wrong; CI's message names the command" do
    recorded = { "a" => { "digest" => "1", "captured_on" => "2026-11-20" }, "b" => { "digest" => "2", "captured_on" => "2026-11-20" },
                 "gone" => { "digest" => "3", "captured_on" => "2026-11-20" } }
    stale = HelpCentre::Screenshots.stale({ "a" => "1", "b" => "changed", "new" => "4" }, recorded).to_h
    assert_equal [ "b", "new", "gone" ], stale.keys
    assert_includes stale["b"], "changed since it was captured on 2026-11-20"
    assert_equal "bin/help-screenshots", HelpCentre::Screenshots::COMMAND
    task = Rails.root.join("lib/tasks/help.rake").read
    assert_includes task, "Capture them again with \#{shots::COMMAND}"
    assert_includes task, "docs/runbooks/help-screenshots.md"
    assert Rails.root.join("docs/runbooks/help-screenshots.md").exist?
  end

  test "the demo world only runs in a database of its own" do
    error = assert_raises(RuntimeError) { HelpCentre::Screenshots.in_demo_world { flunk } }
    assert_includes error.message, "bin/help-screenshots"
  end

  test "screenshot placeholders are filled from the demo records" do
    business = Business.create!(name: HelpCentre::Screenshots::BUSINESS, owner: users(:one), timezone: "America/New_York", currency: "USD")
    client = Tenancy.with_business(business) { Client.create!(display_name: "Maria Lopez", contact_methods_attributes: [ { kind: "email", value: "maria@example.com" } ]) }
    shot = HelpCentre::Screenshot.new(name: "x", path: "/admin/clients/:client/edit", as: "owner", region: "main", records: { "client" => "Maria Lopez" })
    assert_equal "/admin/clients/#{client.to_param}/edit", HelpCentre::Screenshots.path_for(shot)
  end
end
