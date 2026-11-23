# Axe-core accessibility checks for system tests (QA #274), shared by AccessibilityTest and
# feature tests that check a page in a state only a browser reaches (PLT-22's chosen logo).
module AxeHelpers
  AXE = Pathname(Gem.loaded_specs.fetch("axe-core-api").full_gem_path).join("node_modules/axe-core/axe.min.js")

  # Runs axe (WCAG 2.1 A/AA and best practices: heading order, landmarks, content in a region)
  # on each page, and fails once, listing every page's problems.
  def assert_accessible(*paths)
    problems = paths.flat_map do |path|
      visit path
      axe_problems(path)
    end
    assert_empty problems, "axe found problems:\n#{problems.join("\n")}"
  end

  # Axe on the page as it is now. An open dialog's fade-in (a <dialog>, or the tour's, ACC-08)
  # is let finish first: mid-fade, its text is partly transparent and the contrast check fails falsely.
  def axe_problems(label)
    execute_script(AXE.read) unless evaluate_script("typeof window.axe === 'object'")
    evaluate_async_script(<<~JS).map { "#{label}: #{_1}" }
      const done = arguments[0]
      const fading = [...document.querySelectorAll("dialog[open], [role=dialog]:not([hidden])")].flatMap((d) => d.getAnimations({ subtree: true }))
      Promise.all(fading.map((a) => a.finished))
        .then(() => axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa", "best-practice"] } }))
        .then((r) => done(r.violations.map((v) => `${v.id} (${v.help}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`)))
    JS
  end
end
