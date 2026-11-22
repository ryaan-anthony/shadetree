require "test_helper"

# The admin design system (#314), checked on every page in the shared list (StaffPages),
# rendered as an Owner. PLT-14: button ranks. PLT-15 to PLT-22 add their checks here.
class Admin::DesignSystemTest < ActionDispatch::IntegrationTest
  # PLT-14: labels that are always Destructive (outside a menu, where Archive stays a menu item).
  DESTRUCTIVE = /\A(Cancel job|Disconnect|Deactivate|Archive|Delete)\b/

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  # Built on first use, so a test can visit the empty lists first.
  def pages = @pages ||= StaffPages.build(@business, @owner)

  # Renders each page and collects what the block finds wrong, failing once with every page's problems.
  def assert_each_page(pages = self.pages)
    problems = pages.flat_map do |page|
      get page.path
      next [ "#{page}: #{response.status}" ] unless response.successful?

      yield(Nokogiri::HTML5(response.body)).map { "#{page}: #{_1}" }
    end
    assert_empty problems, problems.join("\n")
  end

  def label(node) = node.text.squish.presence || node["value"].to_s.squish.presence || node["aria-label"].to_s
  def buttons(scope) = scope.css("a.btn, button.btn, input.btn, span.btn")

  test "the page list renders" do
    assert_operator pages.size, :>, 60
    assert_each_page { [] }
  end

  test "a page header has at most one Primary, outside its dialogs" do
    assert_each_page do |html|
      primaries = html.css(".page-head .btn-primary").reject { _1.ancestors("dialog").any? }
      primaries.size > 1 ? [ "#{primaries.size} Primary buttons: #{primaries.map { label(_1) }.join(", ")}" ] : []
    end
  end

  test "Cancel on a form or dialog is Tertiary" do
    assert_each_page do |html|
      buttons(html).select { label(_1) == "Cancel" }.reject { _1["class"].split.include?("btn-tertiary") }
                   .map { "Cancel is #{_1["class"]}" }
    end
  end

  test "Cancel job, Disconnect, Deactivate, Archive and every delete are Destructive" do
    assert_each_page do |html|
      buttons(html).select { label(_1).match?(DESTRUCTIVE) }
                   .reject { (_1["class"].split & %w[btn-destructive btn-destructive-solid]).any? }
                   .map { "#{label(_1).inspect} is #{_1["class"]}" }
    end
  end

  test "an empty state's call to action has its page action's rank and wording" do
    check = lambda do |html|
      header = buttons(html.css(".page-head")).index_by { _1["href"] }
      buttons(html.css(".empty")).filter_map do |cta|
        action = header[cta["href"]] if cta["href"]
        next unless action
        next if label(action) == label(cta) && action["class"].split.sort == cta["class"].split.sort

        "empty state's #{label(cta).inspect} (#{cta["class"]}) differs from the page's #{label(action).inspect} (#{action["class"]})"
      end
    end
    assert_each_page(StaffPages.empty, &check)
    assert_each_page(&check)
  end

  test "moving to another record is never Primary" do
    assert_each_page(pages.select(&:detail?)) do |html|
      html.css(".page-head a.btn-primary").filter_map do |link|
        "#{label(link).inspect} goes to another record" if link["href"].to_s.match?(%r{\A/admin/(quotes|jobs|invoices|clients|requests)/[^/]+\z})
      end
    end
  end

  # PLT-14 decisions (owner, 2026-11-22): the quote page's Primary is the next step.
  test "the quote page's Primary: Create job, then Create invoice, then none" do
    primaries = pages.select { _1.name.start_with?("Quote: ") }.to_h do |page|
      get page.path
      [ page.name.delete_prefix("Quote: "), css_select(".page-head .btn-primary").reject { _1.ancestors("dialog").any? }.map { _1.text.squish } ]
    end
    assert_equal({ "sent" => [], "changes requested" => [], "approved, no job" => [ "Create job" ],
                   "job, no invoice" => [ "Create invoice" ], "job and invoice" => [] }, primaries)
    assert_select ".page-head a.btn-secondary", /\AJob J-\d+\z/ # the last quote's job and invoice are links
    assert_select ".page-head a.btn-secondary", /\AInvoice INV-\d+\z/
  end

  test "the client page: New quote is the header's Primary; New job and New invoice are Secondary in Work" do
    get pages.find { _1.name == "Client" }.path
    assert_select ".page-head .btn-primary", count: 1, text: "New quote"
    assert_select ".page-head button.btn-destructive", "Archive"
    assert_select ".page-head .menu .menu-item", text: "Archive", count: 0
    work = css_select("section.card").find { _1.at_css(".card-title")&.text == "Work" }
    assert_equal [ "New job", "New invoice" ], work.css(".card-head .btn").map { _1.text.squish }
    assert work.css(".card-head .btn").all? { _1["class"].include?("btn-secondary") }

    get pages.find { _1.name == "Client: archived" }.path
    assert_select ".page-head .btn-primary", 0
    assert_select ".page-head button.btn-secondary", "Restore"
  end

  test "the job page: Cancel job is Destructive, and its dialog confirms in solid red beside a Tertiary Keep job" do
    get pages.find { _1.name == "Job: open, with a visit" }.path
    assert_select ".page-head button.btn-destructive", "Cancel job"
    assert_select "dialog#job-cancel input.btn-destructive-solid[value='Cancel job']"
    assert_select "dialog#job-cancel button.btn-tertiary", "Keep job"
  end
end
