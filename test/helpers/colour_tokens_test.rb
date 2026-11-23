require "test_helper"

# PLT-17: colours come only from the theme's tokens (app/assets/tailwind/theme.css). This scans
# the staff views, the helpers and the kit's stylesheet, outside comments, for a hex colour, an
# arbitrary colour value (bg-[#f4f5f7]), a translucent rgb()/hsl() or a raw Tailwind palette
# class or variable (bg-slate-50, var(--color-slate-300)). White is allowed. The brand helper is
# exempt (Shadetree's own logo colours), and Branding's presets are business data in the model.
class ColourTokensTest < ActiveSupport::TestCase
  ROOT = Rails.root
  FILES = %w[app/views/admin/**/*.erb app/views/ops/**/*.erb app/views/components/**/*.erb app/views/layouts/app/**/*.erb
             app/views/layouts/app.html.erb app/views/layouts/ops.html.erb app/helpers/**/*.rb app/assets/tailwind/components.css].freeze
  EXEMPT = %w[app/helpers/brand_helper.rb].freeze

  PALETTE = %w[slate gray zinc neutral stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple
               fuchsia pink rose black].freeze
  PREFIXES = %w[bg text border border-t border-r border-b border-l border-x border-y ring ring-offset fill stroke from via to divide
                outline decoration accent caret shadow placeholder].freeze
  WHITE = /\A#(fff|ffffff)\z/i

  def tokens = @tokens ||= ROOT.join("app/assets/tailwind/theme.css").read.scan(/--color-([a-z0-9-]+):/).flatten.to_set

  # The source without comments: ERB <%# %>, HTML <!-- -->, CSS /* */ and Ruby's "# …".
  def code(path, text)
    text = text.gsub(%r{/\*.*?\*/}m) { _1.gsub(/[^\n]/, " ") } if path.end_with?(".css")
    text = text.gsub(/<%#.*?%>/m) { _1.gsub(/[^\n]/, " ") }.gsub(/<!--.*?-->/m) { _1.gsub(/[^\n]/, " ") } if path.end_with?(".erb")
    text = text.gsub(/(^|\s)#(\s.*)?$/, '\1') if path.end_with?(".rb")
    text
  end

  def problems_in(line)
    found = []
    # Hex colours; an issue number (#274) or an anchor (#add-property) isn't one.
    line.scan(/(?<![\w&\/\[])#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})\b(?![-\w])/) do
      hex = Regexp.last_match[0]
      found << "hex colour #{hex}" unless hex.match?(WHITE) || hex.match?(/\A#\d{3,4}\z/)
    end
    line.scan(/-\[(?:#[0-9a-fA-F]{3,8}|(?:color:)?(?:rgb|hsl|oklch)\([^\]]*)\]/) { found << "arbitrary colour #{Regexp.last_match[0]}" }
    line.scan(/\b(?:rgba?|hsla?)\([^)]*\)/) { found << Regexp.last_match[0] unless Regexp.last_match[0].match?(/\Argba?\(255[ ,]+255[ ,]+255\b/) }
    line.scan(/(?<![\w-])(?:#{PREFIXES.join("|")})-((?:#{PALETTE.join("|")})(?:-\d{2,3})?)(?![\w-])/) do
      found << "palette class #{Regexp.last_match[0]}" unless tokens.include?(Regexp.last_match[1])
    end
    line.scan(/var\(--color-([a-z]+-\d{2,3})\)/) { found << "palette variable --color-#{Regexp.last_match[1]}" unless tokens.include?(Regexp.last_match[1]) }
    found
  end

  test "staff views, helpers and the kit take colours only from the theme's tokens" do
    files = FILES.flat_map { Dir[ROOT.join(_1)] }.uniq.map { Pathname(_1).relative_path_from(ROOT).to_s } - EXEMPT
    assert_operator files.size, :>, 200
    offenders = files.flat_map do |path|
      code(path, ROOT.join(path).read).lines.each_with_index.flat_map do |line, index|
        problems_in(line).map { "#{path}:#{index + 1}: #{_1}" }
      end
    end
    assert_empty offenders, offenders.join("\n")
  end

  test "the scan catches each kind and allows white and tokens" do
    assert_equal [ "hex colour #e2e8f0" ], problems_in("color: #e2e8f0;")
    assert_equal [ "arbitrary colour -[#f4f5f7]" ], problems_in('class="bg-[#f4f5f7]"')
    assert_equal [ "palette class bg-slate-50" ], problems_in('class="hover:bg-slate-50"')
    assert_equal [ "palette class bg-black" ], problems_in('class="bg-black/60"')
    assert_equal [ "palette variable --color-slate-300" ], problems_in("border-color: var(--color-slate-300);")
    assert_equal [ "rgb(15 23 42 / 0.4)" ], problems_in("background: rgb(15 23 42 / 0.4);")
    assert_empty problems_in('color: #fff; background: rgb(255 255 255 / 0.1); class="bg-violet-50 text-warning bg-info-50/40"')
    assert_empty problems_in('QA #274 <a href="#add-property">')
  end
end
