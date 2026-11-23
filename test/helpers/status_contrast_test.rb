require "test_helper"

# PLT-17: every status pill's words meet WCAG AA (4.5:1) on white and on its own tint, and the
# calendar's status blocks meet it on theirs. Colours are read from the token file and the kit.
class StatusContrastTest < ActiveSupport::TestCase
  THEME = Rails.root.join("app/assets/tailwind/theme.css").read
  KIT = Rails.root.join("app/assets/tailwind/components.css").read
  TOKENS = THEME.scan(/--color-([a-z0-9-]+):\s*(#[0-9a-f]{6})/i).to_h

  def hex(name) = TOKENS.fetch(name) { flunk "no token --color-#{name}" }

  def luminance(hex)
    hex.delete("#").scan(/../).map { _1.to_i(16) / 255.0 }.map { _1 <= 0.03928 ? _1 / 12.92 : ((_1 + 0.055) / 1.055)**2.4 }
       .zip([ 0.2126, 0.7152, 0.0722 ]).sum { _1 * _2 }
  end

  def contrast(a, b) = [ luminance(a), luminance(b) ].sort.reverse.then { (_1 + 0.05) / (_2 + 0.05) }

  # [background, text] tokens of a rule in the kit; edge: its border colour as well.
  def colours(selector, edge: false)
    rule = KIT[/#{Regexp.escape(selector)} \{([^}]*)\}/m, 1] or flunk "no rule #{selector}"
    found = [ rule[/background: var\(--color-([a-z0-9-]+)\)/, 1], rule[/(?<![-\w])color: var\(--color-([a-z0-9-]+)\)/, 1] ]
    edge ? found + [ rule[/border-color: var\(--color-([a-z0-9-]+)\)/, 1] ] : found
  end

  test "every pill's words are AA on white and on its tint" do
    ComponentsHelper::BADGE_TONES.each do |tone|
      background, text = colours(tone == :neutral ? ".badge" : ".badge-#{tone}")
      assert_operator contrast(hex(text), "#ffffff"), :>=, 4.5, "#{tone} on white"
      assert_operator contrast(hex(text), hex(background)), :>=, 4.5, "#{tone} on its tint"
    end
  end

  test "the calendar's status blocks are AA on their tints" do
    %w[scheduled in-progress completed].each do |status|
      background, text = colours(".cal-status-#{status}")
      assert_operator contrast(hex(text), hex(background)), :>=, 4.5, status
    end
  end

  # Owner, 2026-11-23: In progress is a clearly deeper blue than Scheduled, in its fill and its edge.
  test "In progress and Scheduled are told apart on the calendar" do
    progress_fill, _, progress_edge = colours(".cal-status-in-progress", edge: true)
    scheduled_fill, _, scheduled_edge = colours(".cal-status-scheduled", edge: true)
    assert_operator luminance(hex(progress_fill)), :<, luminance(hex(scheduled_fill)), "In progress's fill is the deeper one"
    assert_operator contrast(hex(progress_fill), hex(scheduled_fill)), :>=, 1.5, "fills"
    assert_operator contrast(hex(progress_edge), hex(scheduled_edge)), :>=, 2.0, "edges"
  end

  test "the contrast sum is right" do
    assert_in_delta 21.0, contrast("#000000", "#ffffff"), 0.01
    assert_in_delta 5.27, contrast(hex("muted"), "#ffffff"), 0.01 # theme.css's note
  end
end
