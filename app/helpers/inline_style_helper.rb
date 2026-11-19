# PLT-13: the content security policy blocks style="" attributes, so values only known at render
# time (a brand color, where a visit sits on the calendar) become classes backed by one nonced
# <style> block. Views call inline_style(css) for a class name and inline_styles_tag once after
# the elements that use it, so the block travels with them in Turbo frames and streams.
module InlineStyleHelper
  UNSAFE = /[<>{}\\]|\/\*/

  # A class name for these declarations, e.g. inline_style("top: 64px; height: 32px").
  def inline_style(declarations)
    css = declarations.to_s.strip
    raise ArgumentError, "inline_style takes declarations, not markup or rules" if css.match?(UNSAFE)

    name = "is-#{Digest::SHA256.hexdigest(css)[0, 12]}"
    (@inline_styles ||= {})[name] ||= css
    name
  end

  # The nonced <style> for every class handed out so far; nothing when there are none. Each
  # call emits only the rules added since the last one.
  def inline_styles_tag
    pending = (@inline_styles || {}).except(*Array(@inline_styles_emitted))
    return if pending.empty?

    @inline_styles_emitted = Array(@inline_styles_emitted) + pending.keys
    rules = pending.map { |name, css| ".#{name}{#{css}}" }.join("\n")
    tag.style(rules.html_safe, nonce: content_security_policy_nonce)
  end

  # A nonced <style> with one rule, for a whole-page element such as the client layout's <body>.
  def inline_style_rule(selector, declarations)
    css = declarations.to_s.strip
    raise ArgumentError, "inline_style_rule takes declarations, not markup or rules" if css.match?(UNSAFE) || selector.match?(UNSAFE)

    tag.style("#{selector}{#{css}}".html_safe, nonce: content_security_policy_nonce)
  end
end
