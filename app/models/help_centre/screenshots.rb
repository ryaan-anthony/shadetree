# OPS-06: the help articles' screenshots, made from the demo seed data and kept in step with
# the screens they show. Both halves run in a database of their own holding only the demo data
# (bin/help-screenshots sets it up), with the clock stopped at DEMO_TIME, so every run sees the
# same screens:
#
# - digests: each screenshot's screen is rendered without a browser (a request through the
#   app) and its region's HTML hashed, with what changes from run to run taken out (uids,
#   tokens, CSRF tokens, nonces, asset digests, dates and times). They're kept in DIGESTS.
# - capture: headless Chrome (Ferrum, ADR 0010) photographs each region at 1280 and 390 wide,
#   saved as WebP under 200 KB in the help image folder.
#
# CI renders the digests again and fails when a screen has changed since its capture
# (HelpCentre::Checks), naming the command that captures it again.
module HelpCentre::Screenshots
  DEMO_TIME = Time.utc(2026, 11, 18, 14) # a Wednesday, 9 am at the demo business
  DIGESTS = "screenshots.yml"
  COMMAND = "bin/help-screenshots"
  MAX_BYTES = 200_000
  PASSWORD = "shadetree-demo-1"
  PUBLIC_HOST = "getshadetree.com"
  # Who's signed in, by the front matter's `as:` (the demo users in db/seeds/development.rb).
  USERS = { "owner" => "owner@example.com", "admin" => "admin@example.com", "technician" => "tech@example.com",
            "new" => "new@example.com" }.freeze
  BUSINESS = "Oakline Lawn & Landscape"
  # A path's placeholders, each found by the value the screenshot gives for it.
  RECORDS = {
    "client" => ->(value) { Client.find_by!(display_name: value) },
    "quote" => ->(value) { Quote.where(title: value).order(:id).first! },
    "job" => ->(value) { Job.where(title: value).order(:id).first! },
    "invoice" => ->(value) { Invoice.find_by!(number: value) },
    "request" => ->(value) { ServiceRequest.find_by!(description: value) },
    "visit" => ->(value) { Visit.joins(:job).where(jobs: { title: value }).order(:scheduled_on, :id).first! }
  }.freeze

  ID_ATTRIBUTES = %w[id for aria-controls aria-labelledby aria-describedby aria-owns aria-activedescendant form list headers].freeze
  # What changes between two runs on the same screens.
  VOLATILE = [
    [ %r{(/assets/[\w./-]+?)-[0-9a-f]{7,}(\.\w+)}, '\1\2' ], # asset digests
    [ /[A-Za-z0-9_\-+\/=]{24,}(?:--[A-Za-z0-9_\-+\/=]+)*/, "TOKEN" ], # signed ids, link tokens, CSRF tokens
    [ /\b[0-9a-f]{8,}\b/, "HEX" ], # random element ids
    [ /\b[1-9A-HJ-NP-Za-km-z]{#{BusinessOwned::UID_LENGTH}}\b/o, "UID" ],
    [ /\bR-[1-9A-HJ-NP-Za-km-z]{8}\b/, "R-REF" ], # a request's reference, from its uid
    [ /\b\d{4}-\d{2}-\d{2}(?:T[\d:.]+(?:Z|[+-]\d{2}:?\d{2})?)?\b/, "DATE" ],
    [ /\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.? \d{1,2}(?:, \d{4})?/, "DATE" ],
    [ /\b\d{1,2}\/\d{1,2}(?:\/\d{2,4})?\b/, "DATE" ],
    [ /\b\d{1,2}(?::\d{2})?\s?(?:am|pm|AM|PM)\b|\b\d{1,2}:\d{2}\b/, "TIME" ]
  ].freeze

  extend self

  def digests_file = HelpCentre.root.join(DIGESTS)
  def recorded = digests_file.exist? ? (YAML.safe_load_file(digests_file, permitted_classes: [ Date ]) || {}) : {}
  def screenshots(library = HelpCentre.library) = library.articles.flat_map(&:screenshots).sort_by(&:name)

  # The screen's region, with what changes between runs taken out, hashed. HELP_SCREENSHOTS_DUMP=dir
  # writes what's hashed to dir/<name>.html, to see what changed.
  def digest(html, region, name: nil)
    text = normalized(html, region)
    if (dir = ENV["HELP_SCREENSHOTS_DUMP"].presence) && name
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{name}.html"), text.gsub("> <", ">\n<"))
    end
    Digest::SHA256.hexdigest(text)
  end

  def normalized(html, region)
    node = Nokogiri::HTML5(html).at_css(region) or raise ArgumentError, "no #{region.inspect} on the page"
    node = node.dup
    node.css("script, template, noscript, meta, input[type=hidden]").each(&:remove)
    node.traverse do |child|
      if child.element?
        child.attribute_nodes.each do |attribute|
          if attribute.name == "nonce" then attribute.remove
          elsif ID_ATTRIBUTES.include?(attribute.name) then attribute.value = "ID" # often random ("picker-9781ea")
          else attribute.value = scrub(attribute.value)
          end
        end
      elsif child.text?
        child.content = scrub(child.content)
      end
    end
    node.to_html.gsub(/\s+/, " ")
  end

  def scrub(text) = VOLATILE.reduce(text) { |result, (pattern, replacement)| result.gsub(pattern, replacement) }

  # Runs the block in the demo world: the demo data loaded, the clock at DEMO_TIME, tips off and
  # the tour done, so neither covers a screen. Only in the database COMMAND sets up for it.
  def in_demo_world(&)
    raise "The demo data belongs in a database of its own (…_help): run #{COMMAND}" unless own_database?

    time_helper.travel_to(DEMO_TIME) do
      quietly do
        load Rails.root.join("db/seeds.rb")
        load Rails.root.join("db/seeds/development.rb")
      end
      # Pro, so the screens show what the articles describe (inviting a fifth person, roles of
      # your own, automations); Starter's limits would show "upgrade" notices instead.
      Business.find_by!(name: BUSINESS).update!(plan: Plan.find_by!(key: "pro"))
      User.update_all(tips_off: true)
      BusinessUser.update_all(tour_status: "finished", tour_offered_at: Time.current, tour_ended_at: Time.current,
                              welcome_dismissed_at: Time.current) # and My day's welcome, so it covers nothing
      yield
    end
  end

  # The path a screenshot opens, its placeholders filled from the demo records.
  def path_for(shot)
    business = Business.find_by!(name: BUSINESS)
    Tenancy.with_business(business) do
      shot.path.gsub(HelpCentre::PLACEHOLDER) { RECORDS.fetch($1).call(shot.records.fetch($1)).to_param }
    end
  end

  # Each screenshot's digest, rendered through the app as its user, in name order.
  def current_digests(shots = screenshots)
    sessions = Hash.new { |hash, as| hash[as] = signed_in_session(as) }
    shots.to_h do |shot|
      session = sessions[shot.as]
      path = path_for(shot)
      status = session.get(path)
      raise "#{shot.name}: #{path} answered #{status}" unless status == 200

      [ shot.name, digest(session.response.body, shot.region, name: shot.name) ]
    end
  end

  # [name, problem] for each screenshot whose screen changed since its capture, or that was
  # never captured; and recorded digests nobody declares any more.
  def stale(current, recorded = self.recorded)
    changed = current.filter_map do |name, digest|
      entry = recorded[name]
      if entry.nil? then [ name, "hasn't been captured" ]
      elsif entry["digest"] != digest then [ name, "shows a screen that has changed since it was captured on #{entry["captured_on"]}" ]
      end
    end
    changed + (recorded.keys - current.keys).map { [ _1, "is recorded but no article declares it" ] }
  end

  # Captures the given screenshots and records every digest. Needs Chrome.
  def capture!(current, names, captured_on:)
    shots = screenshots.select { names.include?(_1.name) }
    Browser.new.capture(shots) { |shot| path_for(shot) } if shots.any?
    entries = recorded.slice(*current.keys)
    names.each { |name| entries[name] = { "digest" => current.fetch(name), "captured_on" => captured_on.iso8601 } }
    digests_file.write("# OPS-06: written by #{COMMAND}; each screenshot's screen digest when it was captured.\n" +
                       entries.sort.to_h.to_yaml.delete_prefix("---\n"))
  end

  def own_database? = !Rails.env.production? && ActiveRecord::Base.connection_db_config.database.to_s.end_with?("_help")

  private

  def time_helper
    require "active_support/testing/time_helpers"
    @time_helper ||= Object.new.extend(ActiveSupport::Testing::TimeHelpers)
  end

  def quietly
    original = $stdout.dup
    $stdout.reopen(File::NULL)
    yield
  ensure
    $stdout.reopen(original)
  end

  def signed_in_session(as)
    ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
      session.host! "www.example.com"
      session.post "/users/sign_in", params: { user: { email: USERS.fetch(as), password: PASSWORD } }
      raise "Couldn't sign in as #{as}" unless session.response.redirect?

      # Land, so "Signed in successfully." is shown here and not over the first screenshot.
      3.times { session.response.redirect? ? session.follow_redirect! : break }
    end
  end

  # Headless Chrome on the app, served in this process (as system tests are), so it sees the
  # same database and the same stopped clock.
  class Browser
    # Links in the pictures (a request form's address, a client link) show the real site, not the
    # capture's local server. Only in the capturing process; redirects to paths aren't affected.
    module PublicHost
      def default_url_options = super.merge(host: HelpCentre::Screenshots::PUBLIC_HOST, protocol: "https", port: nil)
    end

    def capture(shots)
      require "capybara"
      ApplicationController.prepend(PublicHost) unless ApplicationController < PublicHost
      Capybara.server = :puma, { Silent: true }
      server = Capybara::Server.new(Rails.application).boot
      base = "http://#{server.host}:#{server.port}"
      browser = Ferrum::Browser.new(browser_path: ENV["BROWSER_PATH"].presence, headless: "new", timeout: 30, process_timeout: 60,
                                    window_size: [ 1280, 900 ], browser_options: { "no-sandbox" => nil, "disable-gpu" => nil, "disable-dev-shm-usage" => nil,
                                                                                   "hide-scrollbars" => nil, "force-device-scale-factor" => "1" })
      shots.group_by(&:as).each do |as, list|
        context = browser.contexts.create
        page = context.create_page
        sign_in(page, base, as)
        list.each { |shot| HelpCentre::WIDTHS.each { |width| save(page, base + yield(shot), shot, width) } }
        context.dispose
      end
    ensure
      browser&.quit
    end

    private

    # The browser takes the cookies of a session signed in through the app.
    def sign_in(page, base, as)
      page.go_to("#{base}/up")
      HelpCentre::Screenshots.send(:signed_in_session, as).cookies.to_hash.each do |name, value|
        page.command("Network.setCookie", name:, value: Rack::Utils.escape(value), url: base, path: "/", httpOnly: true)
      end
    end

    def save(page, url, shot, width)
      page.set_viewport(width:, height: 900)
      page.command("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
      page.go_to(url)
      page.network.wait_for_idle(timeout: 10)
      50.times do
        break if page.evaluate("document.fonts.status") == "loaded" && page.at_css("html[data-controllers-loaded]")

        sleep 0.2
      end
      raise "#{shot.name}: #{url} went to #{page.current_url}" unless page.current_url == url
      raise "#{shot.name}: no #{shot.region} at #{url}" unless page.at_css(shot.region)
      raise "#{shot.name}: shows the capture's local address" if page.at_css(shot.region).text.match?(/127\.0\.0\.1|localhost/)

      # Chrome paints only what's in the window: make it as tall as the page, so a long region
      # is captured whole.
      height = page.evaluate("document.documentElement.scrollHeight").to_i
      page.set_viewport(width:, height: height.clamp(900, 8000)) if height > 900

      png = Base64.decode64(page.screenshot(selector: shot.region, format: "png", encoding: :base64))
      HelpCentre.image_root.mkpath
      HelpCentre.image_root.join("#{shot.name}-#{width}.webp").binwrite(webp(png, shot))
    end

    # WebP under MAX_BYTES: lower quality first, then smaller.
    def webp(png, shot)
      require "vips"
      image = Vips::Image.new_from_buffer(png, "")
      [ 82, 70, 58, 46 ].each do |quality|
        data = image.webpsave_buffer(Q: quality, strip: true)
        return data if data.bytesize <= MAX_BYTES
      end
      raise "#{shot.name}: over #{MAX_BYTES / 1000} KB even at low quality; capture a smaller region" if image.width < 400

      webp(image.resize(0.85).pngsave_buffer, shot)
    end
  end
end
