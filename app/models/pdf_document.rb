# Builds the HTML a PdfRenderer prints: a document template in the "pdf" layout, with the
# app's stylesheet, the Public Sans font and images inlined, so Chrome needs no network.
module PdfDocument
  FONT = "public-sans-latin-wght-normal.woff2"

  def self.render(template, **assigns)
    ApplicationController.renderer.new("HTTP_HOST" => url_options[:host], "HTTPS" => url_options[:protocol] == "https" ? "on" : "off")
                         .render(template:, layout: "pdf", assigns:)
  end

  # Inline <style>: the compiled stylesheet, minus its font URLs, plus the font as data.
  def self.stylesheet
    css = Rails.application.assets.load_path.find("tailwind.css")&.content.to_s.dup.force_encoding(Encoding::UTF_8)
    font = Rails.application.assets.load_path.find(FONT)&.content
    css = css.gsub(/@font-face\s*\{[^}]*\}/, "")
    font_face = font ? %(@font-face{font-family:"Public Sans";font-style:normal;font-weight:100 900;src:url(data:font/woff2;base64,#{Base64.strict_encode64(font)}) format("woff2")}) : ""
    font_face + css
  end

  def self.data_url(blob_or_variant)
    file = blob_or_variant.respond_to?(:processed) ? blob_or_variant.processed : blob_or_variant
    data = file.respond_to?(:download) ? file.download : file.image.download
    content_type = file.respond_to?(:content_type) ? file.content_type : file.image.blob.content_type
    "data:#{content_type};base64,#{Base64.strict_encode64(data)}"
  end

  def self.url_options = ActionMailer::Base.default_url_options.presence || { host: "localhost" }
end
