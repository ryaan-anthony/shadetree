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
    html.css(".rail .truncate, .rail .break-all").map { "the rail cuts #{_1.text.squish.truncate(40).inspect} (#{_1["class"]})" }.uniq
  end

  check :rail_metadata_is_muted do |_page, html|
    html.css(".rail time").filter_map do |time|
      holder = [ time, *time.ancestors ].find { |node| node.element? && classes(node).grep(TONE).any? }
      tone = holder && classes(holder).grep(TONE).first
      next if tone.in?(%w[text-muted text-danger text-warning])

      "the rail's #{holder&.text&.squish&.truncate(50).inspect} gives its date #{tone || "no tone"}, not text-muted"
    end.uniq
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
