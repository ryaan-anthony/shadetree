require "test_helper"

# The admin design system (#314), checked on every page in the shared list (StaffPages):
# each page is rendered once, as an Owner (the operator console as an operator), and every
# registered check runs on it. PLT-14 registers the button ranks; PLT-15 to PLT-22 add theirs
# with `check`, and they run in the same pass.
class Admin::DesignSystemTest < ActionDispatch::IntegrationTest
  CHECKS = {}

  # Registers a check: the block gets the page (StaffPages::Page) and its HTML (Nokogiri) and
  # returns a list of problems. if: limits it to the pages it's true for.
  def self.check(name, if: ->(_page) { true }, &block)
    CHECKS[name] = [ binding.local_variable_get(:if), block ]
  end

  # PLT-14: labels that are always Destructive. Menus keep their own items: Archive in the
  # quote, service, location, tax-rate and client menus, and Delete in the client, draft quote
  # and draft invoice menus (owner, 2026-11-22), so only kit buttons are checked.
  DESTRUCTIVE = /\A(Cancel job|Disconnect|Deactivate|Archive|Delete)\b/
  DISMISS = '[data-action~="modal#close"], button[value=cancel]'.freeze

  def label(node) = node.text.squish.presence || node["value"].to_s.squish.presence || node["aria-label"].to_s
  def kit_buttons(scope) = scope.css("a.btn, button.btn, input.btn, span.btn")
  def classes(node) = node["class"].to_s.split
  def outside_dialogs(nodes) = nodes.reject { _1.ancestors("dialog").any? }

  # The record a link opens, or nil when it isn't a record's own page (its show action).
  def record_link?(href)
    route = Rails.application.routes.recognize_path(href.to_s)
    route[:action] == "show" && route[:id].present?
  rescue ActionController::RoutingError
    false
  end

  check :page_header, if: :head.to_proc do |_page, html|
    html.at_css(".page-head") ? [] : [ "no page header (.page-head); opt it out in StaffPages if that's intended" ]
  end

  check :one_primary_in_the_header do |_page, html|
    primaries = outside_dialogs(html.css(".page-head .btn-primary"))
    primaries.size > 1 ? [ "#{primaries.size} Primary buttons in the header: #{primaries.map { label(_1) }.join(", ")}" ] : []
  end

  check :never_primary_to_another_record do |_page, html|
    outside_dialogs(html.css(".page-head a.btn-primary")).filter_map do |link|
      "#{label(link).inspect} is Primary but opens another record" if record_link?(link["href"])
    end
  end

  check :cancel_is_tertiary do |_page, html|
    kit_buttons(html).select { _1.matches?(DISMISS) || label(_1) == "Cancel" }
                     .reject { classes(_1).include?("btn-tertiary") }
                     .map { "#{label(_1).inspect} dismisses but is #{_1["class"]}" }
  end

  check :destructive_labels do |_page, html|
    kit_buttons(html).select { label(_1).match?(DESTRUCTIVE) }
                     .reject { (classes(_1) & %w[btn-destructive btn-destructive-solid]).any? }
                     .map { "#{label(_1).inspect} is #{_1["class"]}" }
  end

  # Owner, 2026-11-22: confirm dialogs use the Primary for safe actions and solid red only for these.
  DESTRUCTIVE_CONFIRM = /\A(Delete|Remove|Revoke|Disconnect|Deactivate|Suspend|Discard|Undo import|Cancel job|Cancel visit|Void)\b/

  check :confirm_variant_matches_the_action do |_page, html|
    html.css("[data-turbo-confirm-button]").filter_map do |node|
      destructive = node["data-turbo-confirm-variant"] == "destructive"
      wanted = node["data-turbo-confirm-button"].match?(DESTRUCTIVE_CONFIRM)
      next if destructive == wanted

      "confirming #{node["data-turbo-confirm-button"].inspect} is #{destructive ? "red" : "the Primary"}"
    end
  end

  check :empty_state_matches_the_page_action do |_page, html|
    header = kit_buttons(html.css(".page-head")).index_by { _1["href"] }
    kit_buttons(html.css(".empty")).filter_map do |cta|
      action = header[cta["href"]] if cta["href"]
      next unless action
      next if label(action) == label(cta) && classes(action).sort == classes(cta).sort

      "empty state's #{label(cta).inspect} (#{cta["class"]}) differs from the page's #{label(action).inspect} (#{action["class"]})"
    end
  end

  setup do
    @business = businesses(:one)
    @owner = users(:one)
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
  end

  # Renders each page once and runs every check on it.
  def sweep(pages)
    pages.flat_map do |page|
      get page.path
      next [ "#{page}: #{response.status}" ] unless response.successful?

      html = Nokogiri::HTML5(response.body)
      CHECKS.flat_map do |name, (applies, block)|
        applies.call(page) ? instance_exec(page, html, &block).map { "#{page} [#{name}]: #{_1}" } : []
      end
    end
  end

  test "every staff page passes the design-system checks" do
    problems = sweep(StaffPages.empty) # before any records exist
    pages = StaffPages.build(@business, @owner)
    problems += sweep(pages.reject(&:ops?))
    sign_in_operator(@owner)
    problems += sweep(pages.select(&:ops?))
    assert_empty problems, problems.join("\n")
  end
end
