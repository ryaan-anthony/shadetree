require "test_helper"

# PLT-19: tabs, the segmented control and the menu.
class ControlsHelperTest < ActionView::TestCase
  include ComponentsHelper
  include IconsHelper
  FILTERS = { "all" => "All", "awaiting" => "Awaiting", "approved" => "Approved", "declined" => "Declined" }.freeze

  def html(markup) = Nokogiri::HTML5.fragment(markup)

  test "link tabs mark the current one and show counts" do
    nav = html(tabs(FILTERS, current: "awaiting", label: "Show quotes", counts: FILTERS.keys.index_with(2), href: ->(key) { "/q?filter=#{key}" })).at_css("nav.tabs")
    assert_equal "Show quotes", nav["aria-label"]
    assert_equal "tabs", nav["data-controller"]
    assert_equal [ "Awaiting 2" ], nav.css("a.tab[aria-current=page]").map { _1.text.squish }
    assert_equal "/q?filter=approved", nav.css("a.tab")[2]["href"]
    assert_equal %w[2 2 2 2], nav.css(".tab-count").map(&:text)
  end

  # Owner, 2026-11-22: zero-count tabs are hidden, except "All" and the current one.
  test "tabs at 0 are hidden except All and the current tab" do
    counts = { "all" => 0, "awaiting" => 0, "approved" => 3, "declined" => 0 }
    nav = html(tabs(FILTERS, current: "declined", label: "Show", counts:, href: ->(key) { "/#{key}" }))
    assert_equal %w[All Approved Declined], nav.css(".tab").map { _1.children.first.text.strip }
  end

  test "tabs without counts are all shown, and keep: names the always-shown tabs" do
    choices = { "active" => "Active", "archived" => "Archived" }
    assert_equal 2, html(tabs(choices, current: "active", label: "Show", href: ->(key) { "/#{key}" })).css(".tab").size
    nav = html(tabs(choices, current: "active", label: "Show", counts: { "archived" => 0 }, keep: %w[active], href: ->(key) { "/#{key}" }))
    assert_equal [ "Active" ], nav.css(".tab").map { _1.text.squish }
  end

  test "a filter form's tabs are submit buttons with aria-pressed" do
    nav = html(tabs(FILTERS, current: "all", label: "Show", name: "filter", data: { tabs_target: "row" })).at_css("nav")
    assert_nil nav["data-controller"]
    assert_equal "row", nav["data-tabs-target"]
    buttons = nav.css("button.tab[type=submit][name=filter]")
    assert_equal %w[true false false false], buttons.map { _1["aria-pressed"] }
    assert_equal "tabs#press", buttons.first["data-action"]
  end

  test "radio tabs are a fieldset with a legend" do
    set = html(tabs({ "0" => "Active", "1" => "Archived" }, current: "1", label: "Show", radio: { name: "archived", form: "f" })).at_css("fieldset.tabs")
    assert_equal "Show", set.at_css("legend").text
    assert_equal [ "1" ], set.css("label.tab.tab-radio input[type=radio][form=f][checked]").map { _1["value"] }
  end

  test "the segmented control in each of its kinds" do
    links = html(segmented_control({ "day" => "Day", "week" => "Week" }, selected: "week", label: "View", href: ->(key) { "/s?view=#{key}" }))
    assert_equal "View", links.at_css("ul.segmented")["aria-label"]
    assert_equal [ "Week" ], links.css("li > a.segment[aria-current=page]").map(&:text)

    buttons = html(segmented_control({ "member" => "Person", "status" => [ "Status", { id: "by-status" } ] }, selected: "status", label: "Color by",
                                     label_id: "color-label", name: "color"))
    group = buttons.at_css("div.segmented[role=group]")
    assert_equal "color-label", group["aria-labelledby"]
    assert_nil group["aria-label"]
    assert_equal %w[false true], group.css("button.segment[type=submit][name=color]").map { _1["aria-pressed"] }
    assert_equal "by-status", group.css("button").last["id"]
    assert_nil group.at_css("button")["data-action"], "only a filter form's tabs carry tabs#press"

    radios = html(segmented_control({ "monthly" => "Monthly", "yearly" => "Yearly" }, selected: "monthly", label: "Pay", radio: { name: "interval" }))
    assert_equal "Pay", radios.at_css("fieldset.segmented legend.sr-only").text
    assert_equal [ "monthly" ], radios.css("label.segment.segment-radio input[checked]").map { _1["value"] }
  end

  test "an option needs a way to be sent" do
    assert_raises(ArgumentError) { segmented_control({ "a" => "A" }, selected: "a", label: "X") }
  end

  test "the menu is a disclosure: its button controls the panel" do
    markup = html(menu(label: "More actions", button: { id: "more", data: { modal_target: "return" } }) { link_to("Edit", "/e", class: "menu-item") })
    button = markup.at_css("button#more")
    panel = markup.at_css(".menu")
    assert_equal "false", button["aria-expanded"]
    assert_equal panel["id"], button["aria-controls"]
    assert_equal "More actions", button["aria-label"]
    assert_nil button["aria-haspopup"], "a disclosure, not an ARIA menu"
    assert_equal "return", button["data-modal-target"]
    assert_equal "button", button["data-menu-target"]
    assert panel.key?("hidden")
    assert_includes panel["class"], "right-0"
    assert_equal "menu", markup.at_css("div.relative")["data-controller"]
    assert_includes markup.at_css("div.relative")["data-action"], "focusout->menu#focusout"

    other = html(menu(label: "More actions") { "" }).at_css(".menu")
    assert_not_equal panel["id"], other["id"], "ids are unique on the page"
  end

  test "a labelled menu button is Secondary with its text" do
    button = html(menu(label: "Actions", text: "Actions", align: :left) { "" }).at_css("button")
    assert_includes button["class"], "btn-secondary"
    assert_nil button["aria-label"]
    assert_equal "Actions", button.text.strip
  end
end
