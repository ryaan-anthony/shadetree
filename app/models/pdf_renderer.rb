# Turns a self-contained HTML document into a PDF with headless Chrome (ADR 0010, QTE-02).
# The HTML must carry its own styles, fonts and images (data: URLs). Chrome is cut off from
# the network (a dead proxy for every scheme, loopback included, plus request interception)
# and runs with scripts off, so a document can't fetch anything or reach internal addresses
# even if content were ever mis-escaped.
#
# Renders take turns, one per process: a render waits at most WAIT for its turn, so a hung
# Chrome fails a few downloads quickly instead of holding every web thread. (Solid Queue runs
# in its own process, so a host renders at most two at once.)
#
#   PdfRenderer.render(html, paper: :a4, footer: "<div>…</div>") # => binary PDF string
class PdfRenderer
  class Error < StandardError; end

  PAPER = { letter: { paper_width: 8.5, paper_height: 11 }, a4: { paper_width: 8.27, paper_height: 11.69 } }.freeze
  # Countries that use US Letter; everyone else uses A4.
  LETTER_COUNTRIES = %w[US CA MX PR PH CL CO VE GT CR PA DO SV].freeze
  TIMEOUT = 15
  WAIT = 10
  TURN = Concurrent::Semaphore.new(1)

  def self.paper_for(country) = LETTER_COUNTRIES.include?(country.to_s.upcase) ? :letter : :a4

  def self.render(html, paper: :letter, footer: nil)
    raise Error, "PDF renderer busy" unless TURN.try_acquire(1, WAIT)

    begin
      print(html, paper:, footer:)
    ensure
      TURN.release
    end
  end

  def self.print(html, paper:, footer:)
    browser = Ferrum::Browser.new(**browser_options)
    page = browser.create_page
    page.network.intercept
    page.on(:request) { |request| request.url.start_with?("data:", "about:") ? request.continue : request.abort }
    page.content = html
    page.pdf(encoding: :binary, **PAPER.fetch(paper), print_background: true,
             margin_top: 0.55, margin_bottom: 0.7, margin_left: 0.55, margin_right: 0.55,
             display_header_footer: footer.present?, header_template: "<span></span>", footer_template: footer.to_s)
  rescue Ferrum::Error, SystemCallError => error # SystemCallError: Chrome missing or not executable
    raise Error, "#{error.class}: #{error.message}"
  ensure
    browser&.quit
  end
  private_class_method :print

  def self.browser_options
    { browser_path: ENV["BROWSER_PATH"].presence, headless: "new", timeout: TIMEOUT, process_timeout: TIMEOUT,
      browser_options: { "no-sandbox" => nil, "disable-gpu" => nil, "disable-dev-shm-usage" => nil,
                         "proxy-server" => "127.0.0.1:9", "proxy-bypass-list" => "<-loopback>",
                         "blink-settings" => "scriptEnabled=false" } }.compact
  end
end
