# OPS-06: the help articles' screenshots. Run through bin/help-screenshots, which sets up the
# database of demo data these need; see HelpCentre::Screenshots.
namespace :help do
  namespace :screenshots do
    desc "Fail when a help screenshot shows a screen that changed since its capture (CI)"
    task check: :environment do
      shots = HelpCentre::Screenshots
      stale = shots.in_demo_world { shots.stale(shots.current_digests) }
      if stale.any?
        articles = HelpCentre.library.articles.flat_map { |article| article.screenshots.map { [ _1.name, article.slug ] } }.to_h
        warn stale.map { |name, problem| "Help screenshot #{name} (in #{articles[name] || "no article"}) #{problem}." }.join("\n")
        abort "Capture them again with #{shots::COMMAND} (or the Help screenshots workflow), then re-read the articles " \
              "named above and update each one's reviewed date. See docs/runbooks/help-screenshots.md."
      end
      puts "#{shots.screenshots.size} help screenshots are current."
    end

    desc "Capture help screenshots that changed or are new (ALL=1: every one)"
    task capture: :environment do
      shots = HelpCentre::Screenshots
      today = Date.current
      shots.in_demo_world do
        current = shots.current_digests
        names = ENV["ALL"].present? ? current.keys : shots.stale(current).map(&:first) & current.keys
        shots.capture!(current, names, captured_on: today)
        puts names.any? ? "Captured #{names.join(", ")}." : "Every help screenshot is current."
      end
    end
  end
end
