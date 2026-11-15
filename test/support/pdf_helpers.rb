# QTE-02: most tests swap Chrome for a fake renderer (fast, no browser needed); the real
# one is exercised by test/models/pdf_renderer_test.rb, which skips without Chrome.
module PdfHelpers
  # Yields the list of render calls ({ html:, paper:, footer: }); each returns a tiny PDF.
  def with_fake_pdf_renderer(fail_with: nil)
    calls = []
    original = PdfRenderer.method(:render)
    PdfRenderer.define_singleton_method(:render) do |html, paper: :letter, footer: nil|
      raise fail_with if fail_with

      calls << { html:, paper:, footer: }
      "%PDF-1.4 fake #{calls.size}\n%%EOF\n"
    end
    yield calls
  ensure
    PdfRenderer.define_singleton_method(:render, original)
  end
end

ActiveSupport.on_load(:active_support_test_case) { include PdfHelpers }
