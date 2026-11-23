require "test_helper"

# The admin design system (#314), checked on every page in the shared list (StaffPages):
# each page is rendered once, as an Owner (the operator console as an operator), and every
# registered check runs on it. PLT-14 registers the button ranks, PLT-15 the page header and type
# scale; PLT-16 to PLT-22 add theirs with `check`, and they run in the same pass.
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

  # PLT-15: one page header, a locked type scale, and no sentence as a heading.
  MONTH = /(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?/
  # A date with its year, a numeric date or a clock time. A day's label on a calendar or agenda
  # ("Monday, Nov 23", "Today") names a group, so it may head one.
  DATE = /\b#{MONTH} \d{1,2}, \d{4}\b|\b\d{1,2}\/\d{1,2}\/\d{2,4}\b|\b\d{1,2}:\d{2}\s?(?:AM|PM)\b/i
  # The steps a heading may use (the style guide's Type section): each kit title class is one.
  STEPS = %w[page-title section-title card-title empty-title modal-title tour-title table-head text-sm2].freeze
  OFF_SIZE = /\A(?:[a-z-]+:)*text-(?:xs|base|lg|[2-9]?xl|\[[\d.]+(?:rem|px|em)\])\z/
  OFF_SCALE = /\A(?:text-(?:xs|sm|base|lg|[2-9]?xl|\[.+\])|font-(?:medium|semibold|bold|extrabold|black))\z/
  # The client's own document, embedded as clients see it, keeps the client pages' type (out of scope).
  def headings(html, levels = "h1, h2, h3, h4, h5, h6") = html.css(levels).reject { _1.ancestors(".quote-doc").any? }
  def visible?(node) = !classes(node).include?("sr-only")

  check :top_bar_is_global_only do |_page, html|
    bar = html.at_css(".topbar")
    title = html.at_css("h1")&.text&.squish
    next [] unless bar

    problems = bar.css("h1, h2, p").map { "the top bar has #{_1.name} #{_1.text.squish.inspect}" }
    problems << "the top bar repeats the H1 #{title.inspect}" if title.present? && bar.text.squish.include?(title)
    problems
  end

  check :one_h1 do |_page, html|
    count = html.css("h1").size
    count == 1 ? [] : [ "#{count} H1s: #{html.css("h1").map { _1.text.squish.inspect }.join(", ")}" ]
  end

  check :h1_in_the_page_header, if: :head.to_proc do |_page, html|
    html.at_css("main .page-head h1.page-title") ? [] : [ "the H1 isn't the page header's, inside main" ]
  end

  check :no_date_in_a_section_heading do |_page, html|
    headings(html, "h2, h3").filter_map { |h| "#{h.name} #{h.text.squish.inspect} has a date" if h.text.squish.match?(DATE) }
  end

  # Record names (quote titles, client names) head their own pages as H1s, so only H2 and H3 are
  # checked; a dialog's title asks its question ("Cancel the visit on …?") by design.
  check :no_sentence_as_a_heading do |_page, html|
    outside_dialogs(headings(html, "h2, h3")).select(&method(:visible?)).filter_map do |h|
      text = h.text.squish
      "#{h.name} #{text.inspect} reads as a sentence" if text.end_with?(".") || text.split.size > 8
    end
  end

  check :sent_panel_title do |_page, html|
    html.css("#sent-panel-h").reject { _1.text.squish == "Sent" }.map { "the sent panel is titled #{_1.text.squish.inspect}, not \"Sent\"" }
  end

  check :headings_on_the_type_scale do |_page, html|
    headings(html).select(&method(:visible?)).filter_map do |h|
      steps = classes(h) & STEPS
      off = classes(h).grep(OFF_SCALE) - STEPS
      next if steps.size == 1 && off.empty? && (steps != [ "page-title" ] || h.name == "h1")

      "#{h.name} #{h.text.squish.truncate(40).inspect} is #{h["class"].inspect}, not one step of the type scale"
    end
  end

  # Owner, 2026-11-23: text off the headings too uses only the scale's steps (body text-sm, small
  # text-sm2, .figure for a stat's number, and the kit's classes), so any other size utility fails.
  check :text_on_the_type_scale do |_page, html|
    html.css("[class]").reject { _1.ancestors(".quote-doc").any? }.filter_map do |node|
      off = classes(node).grep(OFF_SIZE)
      "#{node.name} #{node.text.squish.truncate(40).inspect} has #{off.join(" ")}, off the type scale" if off.any?
    end.uniq
  end

  check :heading_levels_in_order do |_page, html|
    last = 0
    headings(html).each_with_object([]) do |h, problems|
      level = h.name[1].to_i
      problems << "#{h.name} #{h.text.squish.truncate(40).inspect} skips from h#{last}" if level > last + 1 && last.positive?
      last = level
    end
  end

  # PLT-20: each fact once. A detail page's summary strip is the single home for its status, key
  # dates and headline amount.
  def summary(html, id) = html.css("##{id} > div").to_h { [ _1.at_css("dt").text.squish, _1.at_css("dd") ] }
  def card_titled(html, title) = html.css("section.card").find { _1.at_css(".card-title")&.text&.squish == title }
  def repeats(text, facts) = facts.compact_blank.select { text.match?(/(?<!\w)#{Regexp.escape(_1)}(?!\w)/) }

  # The staff quote's document card: lines, totals, message, terms and files. Its lines and totals
  # are the document's own, so only the rest is held against the strip.
  check :quote_document_without_the_summary, if: ->(page) { page.detail? && page.key.start_with?("quote_") } do |_page, html|
    doc = html.at_css("#quote-document")&.dup
    next [ "no quote document (#quote-document)" ] unless doc

    strip = summary(html, "quote-summary")
    problems = doc.css(".quote-doc-title").map { "the document repeats the title #{_1.text.squish.inspect}" }
    doc.css(".quote-doc-lines, .quote-doc-totals").each(&:remove)
    labels = [ "Prepared for", "Property", "Sent on", "Prepared on", "Valid until", "Status" ]
    facts = [ strip["Status"]&.css(".badge")&.map { _1.text.squish }, strip["Valid until"]&.at_css("time")&.text, strip["Total"]&.text ].flatten
    responses = html.css("[id^='response-'] .font-semibold").map { _1.text.squish }
    problems + repeats(doc.text.squish, labels + facts + responses).map { "the document card repeats #{_1.inspect}" }
  end

  check :invoice_balance_once, if: ->(page) { page.detail? && page.key.start_with?("invoice_") } do |_page, html|
    payments = card_titled(html, "Payments")
    next [] unless payments # a void invoice with no payments has none

    labels = payments.css("#payments-total dt").map { _1.text.squish }
    problems = payments.text.include?("Balance") ? [ "the Payments card shows the balance" ] : []
    labels == [ "Paid" ] ? problems : problems << "the Payments card's total is #{labels.inspect}, not just Paid"
  end

  # A client's invoice totals are Work's; Balance sums what's owed and paid, and the Timeline's
  # invoice events don't carry the invoice's total.
  check :client_invoice_totals_in_work, if: ->(page) { page.detail? && page.key.start_with?("client") } do |_page, html|
    problems = []
    balance = card_titled(html, "Balance")
    problems << "the Balance card lists invoices" if balance&.at_css("a[href*='/invoices/'], .badge")
    html.css("#client-timeline li").each do |line|
      text = line.at_css("p")&.text&.squish.to_s
      problems << "the Timeline's #{text.inspect} has an amount" if text.start_with?("Invoice") && text.match?(/\$\d/)
    end
    problems
  end

  # PLT-20: a detail page's side column (.rail) wraps text at spaces, never cuts it, and its
  # metadata (who and when) is muted, a step below the ink of what it describes. Its dates don't
  # wrap (.rail time is nowrap; the system test measures it).
  TONE = /\Atext-(ink|ink-2|body|subtle|muted|faint|danger|warning)\z/

  check :detail_side_column_is_a_rail, if: :detail?.to_proc do |_page, html|
    html.css("main aside").reject { classes(_1).include?("rail") }.map { "an aside isn't a .rail: #{_1["class"].inspect}" }
  end

  check :rail_text_isnt_cut do |_page, html|
    html.css(".rail .truncate, .rail .break-all, .rail .text-ellipsis, .rail [class*='line-clamp-']").map { "the rail cuts #{_1.text.squish.truncate(40).inspect} (#{_1["class"]})" }.uniq
  end

  check :rail_metadata_is_muted do |_page, html|
    html.css(".rail time").filter_map do |time|
      holder = [ time, *time.ancestors ].find { |node| node.element? && classes(node).grep(TONE).any? }
      tone = holder && classes(holder).grep(TONE).first
      next if tone.in?(%w[text-muted text-danger text-warning])

      "the rail's #{holder&.text&.squish&.truncate(50).inspect} gives its date #{tone || "no tone"}, not text-muted"
    end.uniq
  end

  # PLT-16: a page is Wide (the content area's full width, no limit of its own) or Form (.form-split:
  # #303's form column, with an optional aside). Any other max width on a page-level block fails.
  # Widths inside cards, dialogs, tables and fields aren't checked; a block holding form controls
  # and no card is a field (a search box, a date). max-w-prose is a paragraph's measure.
  WIDTH = /\A(?:[a-z0-9-]+:)*max-w-(?!none\z|full\z|prose\z)/
  INSIDE = ".card, dialog, .modal, .menu, table, .field, .quote-doc".freeze
  CONTROLS = "input:not([type=hidden]), select, textarea".freeze
  BLOCKS = ".card, table, section, h2, h3".freeze

  check :page_width_is_a_container do |_page, html|
    html.css("main [class]").reject { _1.ancestors(INSIDE).any? }.filter_map do |node|
      widths = classes(node).grep(WIDTH)
      next if widths.empty? || node.matches?(CONTROLS) || (node.at_css(CONTROLS) && !node.matches?(BLOCKS) && !node.at_css(BLOCKS))

      "#{node.name}.#{classes(node).first(3).join(".")} has #{widths.join(" ")}: use the Wide or Form container"
    end
  end

  # A form page's own two columns (a fixed-width track) are the Form container's aside, not a grid
  # of their own. Detail pages' rails and the schedule are Wide, and the builders are out of scope.
  COLUMNS = /\A(?:[a-z0-9-]+:)*grid-cols-\[[^\]]*\d(?:rem|px)/

  check :form_columns_are_the_form_container, if: ->(page) { page.kind == :form && !page.key.end_with?("_builder") } do |_page, html|
    html.css("main [class]").reject { _1.ancestors(INSIDE).any? || _1.ancestors(".form-split").any? || classes(_1).include?("form-split") }.filter_map do |node|
      columns = classes(node).grep(COLUMNS)
      next if columns.empty? || !(node.matches?(BLOCKS) || node.at_css(BLOCKS))

      "#{node.name}.#{classes(node).first(3).join(".")} has #{columns.join(" ")}: use .form-split with a .form-split-aside"
    end
  end

  # PLT-19: one kit menu, a disclosure (ControlsHelper#menu): its button controls the panel, and
  # the panel takes the width of its longest item (no fixed width).
  check :kit_menus do |_page, html|
    html.css("[data-controller~=menu]").flat_map do |menu|
      panel = menu.at_css("[data-menu-target=menu]")
      button = menu.at_css("[data-menu-target=button]")
      name = button && label(button).presence || "a menu"
      problems = []
      problems << "#{name}: its button doesn't control its panel (aria-controls, aria-expanded)" unless panel && panel["id"] && button &&
                                                                                                       button["aria-controls"] == panel["id"] && button["aria-expanded"]
      problems << "#{name}: aria-haspopup promises an ARIA menu; the kit menu is a disclosure" if button&.[]("aria-haspopup")
      problems << "#{name}: a fixed width (#{panel["class"]}) can wrap its items" if panel && classes(panel).grep(/\A(min-|max-)?w-(?!auto)/).any?
      problems
    end
  end

  # PLT-19: lists search as you type, with no Search button. A <noscript> button is the no-script
  # fallback where Enter would otherwise press a tab; the tabs a filter form submits aren't one.
  LIST = %i[list empty].freeze
  check :search_as_you_type, if: ->(page) { LIST.include?(page.kind) } do |_page, html|
    html.css("form:has(input[type=search])").flat_map do |form|
      buttons = form.css("button:not([type=button]), input[type=submit]").reject { _1.ancestors("noscript").any? || _1.matches?(".tab, .segment") }
      [ ("#{form["id"] || form["action"]}: a Search button (#{buttons.map { label(_1) }.join(", ")})" if buttons.any?),
        ("#{form["id"] || form["action"]}: doesn't search as you type (search-form controller)" unless form["data-controller"].to_s.split.include?("search-form")) ].compact
    end
  end

  # PLT-19: a switch (a pressed button, a current link or a hidden radio) is the kit's tabs or
  # segmented control. Not checked: the sidebar, pagination, the brand colour presets (a colour
  # picker), the top bar's Notifications link and the schedule's Crew list (a list of people with
  # their hours, each row a filter).
  SWITCH = 'main [aria-pressed], main a[aria-current="page"], main a[aria-current="true"], main input[type=radio].sr-only'.freeze
  check :one_switch_style do |_page, html|
    html.css(SWITCH).reject { _1.ancestors(".tabs, .segmented, .pagination, #schedule-members").any? || _1["data-brand-preview-target"] == "swatch" }
        .map { "#{label(_1).presence || _1["value"]} is a switch outside the kit's tabs and segmented control" } +
      html.css(".tab").reject { _1.ancestors(".tabs").any? }.map { "#{label(_1)} is a tab outside .tabs" } +
      html.css(".segment").reject { _1.ancestors(".segmented").any? }.map { "#{label(_1)} is a segment outside .segmented" }
  end

  # PLT-19 (owner, 2026-11-22): zero-count status tabs are hidden, except "All" and the current one.
  check :no_empty_tabs do |_page, html|
    html.css(".tabs .tab:has(.tab-count)").filter_map do |tab|
      next unless tab.at_css(".tab-count").text.strip == "0"
      next if tab.key?("data-tabs-keep") || tab.matches?('[aria-current="page"], [aria-pressed="true"]')

      "#{label(tab)} is shown at 0"
    end
  end

  # PLT-17: a pill with a dot is a status, so it comes from the colour map (status_badge names
  # its entry in data-status) with the map's tone, and says its status in words. Pills without
  # a dot are labels (tags, roles, "Default"). The operator console keeps its own statuses.
  def badge_tone(node) = (classes(node).grep(/\Abadge-(?!plain)/).first || "badge-neutral").delete_prefix("badge-").to_sym

  check :status_pills_follow_the_map, if: ->(page) { !page.ops? } do |_page, html|
    html.css(".badge").reject { classes(_1).include?("badge-plain") }.filter_map do |pill|
      type, status = pill["data-status"].to_s.split(":", 2)
      next "#{pill.text.squish.inspect} is a status pill not from the map (use status_badge)" unless status
      next "#{pill["data-status"]} has no words" if pill.text.squish.empty?

      tone = StatusHelper::MAP.dig(type.to_sym, status)&.first
      "#{pill["data-status"]} is #{badge_tone(pill)}, the map says #{tone.inspect}" unless badge_tone(pill) == tone
    end
  end

  # PLT-21: a card whose main content is empty shows the kit's empty state (icon tile, title,
  # one sentence, at most one action). A one-line muted note is only for a sub-list in a card
  # with other content: a detail page's cards are parts of the record (a request's "Quotes: none
  # yet"), so only the other pages are checked.
  EMPTY_NOTE = /\A(None yet|Nothing\b|No \S+( \S+)? yet\b)/i

  def card_body(node) = node.ancestors.find { classes(_1.parent).include?("card") if _1.parent.respond_to?(:[]) }

  check :empty_states_use_the_kit, if: ->(page) { !page.detail? && !page.ops? } do |_page, html|
    html.css(".card p").filter_map do |note|
      next unless note.text.squish.match?(EMPTY_NOTE) && note.ancestors(".empty").none?
      next if (body = card_body(note)).nil? || body.text.squish != note.text.squish

      "#{note.text.squish.inspect} is a bare note in an empty card (use empty_state)"
    end
  end

  # Built with two actions before PLT-21; which one stays is the owner's call (open question).
  TWO_ACTIONS = [ "No services yet", "No invoices yet" ].freeze

  check :empty_state_shape do |_page, html|
    html.css(".empty").flat_map do |empty|
      title = empty.at_css(".empty-title")&.text&.squish
      next [] if TWO_ACTIONS.include?(title) && kit_buttons(empty).size == 2
      [ ("an empty state without an icon tile" unless empty.at_css(".empty-icon svg")),
        ("an empty state without a title" if title.blank?),
        ("#{title.inspect} has #{kit_buttons(empty).size} actions; an empty state has at most one" if kit_buttons(empty).size > 1) ].compact
    end
  end

  # PLT-21: a banner is a standing condition on the page: one tone (PLT-17's meanings), one icon
  # and at most one link or button. Only an error is role="alert"; a banner that arrives as the
  # result of an action is read through the page's polite region (data-controller="announce"),
  # so no banner is a live region of its own.
  BANNER_TONES = %w[banner-info banner-success banner-warning banner-danger].freeze

  check :banners_follow_the_pattern, if: ->(page) { !page.ops? } do |_page, html|
    html.css(".banner").flat_map do |banner|
      text = banner.text.squish.truncate(50).inspect
      tones = classes(banner) & BANNER_TONES
      actions = banner.css("a, button, input[type=submit]").size
      [ ("#{text} has #{tones.size} tones" unless tones.one?),
        ("#{text} has #{banner.css("> svg").size} icons; a banner has one" unless banner.css("> svg").one?),
        ("#{text} has #{actions} links or buttons; a banner has at most one" if actions > 1),
        ("#{text} is role=alert but not an error (banner-danger)" if banner["role"] == "alert" && tones != [ "banner-danger" ]),
        ("#{text} is role=#{banner["role"]}; announce it through the polite region instead" if banner["role"].in?(%w[status log])) ].compact
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
      page.params ? post(page.path, params: page.params) : get(page.path)
      next [ "#{page}: #{response.status}" ] unless response.status == page.status

      html = Nokogiri::HTML5(response.body)
      CHECKS.flat_map do |name, (applies, block)|
        applies.call(page) ? instance_exec(page, html, &block).map { "#{page} [#{name}]: #{_1}" } : []
      end
    end
  end

  test "PLT-16: the width check flags a page-level width, not one inside a card, dialog or field" do
    applies, block = CHECKS.fetch(:page_width_is_a_container)
    page = StaffPages::Page.new(key: :demo, name: "Demo", path: "/", kind: :form)
    run = ->(body) { applies.call(page) && instance_exec(page, Nokogiri::HTML5("<main>#{body}</main>"), &block) }
    assert_equal 1, run.("<div class='max-w-3xl'><section class='card'></section></div>").size
    assert_equal 1, run.("<form class='mx-auto max-w-lg'><div class='card'><input></div></form>").size
    assert_equal 1, run.("<section class='card lg:max-w-[40rem]'><input></section>").size
    assert_empty run.("<div class='form-split'><aside class='form-split-aside'></aside><form></form></div>")
    assert_empty run.("<div class='card'><div class='max-w-xs'></div></div><dialog><p class='max-w-md'></p></dialog>")
    assert_empty run.("<div class='relative max-w-md'><input type='search'></div><select class='max-w-xs'></select>")
  end

  test "PLT-16: a form page's own fixed-width columns are flagged; the Form container's aren't" do
    applies, block = CHECKS.fetch(:form_columns_are_the_form_container)
    form = StaffPages::Page.new(key: :demo, name: "Demo", path: "/", kind: :form)
    run = ->(body) { instance_exec(form, Nokogiri::HTML5("<main>#{body}</main>"), &block) }
    assert_equal 1, run.("<form class='grid lg:grid-cols-[1fr_24rem]'><div class='card'></div><aside></aside></form>").size
    assert_empty run.("<form class='form-split'><div class='card'><div class='grid sm:grid-cols-[8rem_1fr]'></div></div></form>")
    assert_not applies.call(StaffPages::Page.new(key: :demo, name: "Demo", path: "/", kind: :detail))
  end

  test "every staff page passes the design-system checks" do
    problems = sweep(StaffPages.empty) # before any records exist
    pages = StaffPages.build(@business, @owner)
    problems += sweep(pages.reject(&:ops?))
    states = StaffPages.states(@business).group_by(&:as)
    problems += sweep(states[:owner])
    sign_in member_with_role(:technician)
    post switch_admin_business_path, params: { business: @business.uid }
    problems += sweep(states[:technician])
    sign_in_operator(@owner)
    problems += sweep(pages.select(&:ops?))
    sign_in @owner
    post switch_admin_business_path, params: { business: @business.uid }
    @business.update_columns(suspended_at: Time.current) # last: nothing else opens while it's suspended
    problems += sweep(states[:suspended])
    assert_empty problems, problems.join("\n")
  end
end
