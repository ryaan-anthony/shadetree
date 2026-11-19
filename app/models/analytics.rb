# MKT-04: privacy-respecting analytics with self-hosted Plausible (no cookies, no personal data).
# Configured by ANALYTICS_HOST (https://stats.example.com) and ANALYTICS_DOMAIN (the site as
# registered there); never on in development or test.
#
# Page views come from Plausible's script on public marketing pages only (never the staff app
# or client pages). The funnel's later steps happen in the app, so they're sent from the
# server: Analytics.track("Business Created", request:). Only the event name and a fixed,
# id-free address go out, with the visitor's browser and IP so Plausible can link them to the
# same anonymous visitor as their page views (it hashes these daily and keeps neither).
module Analytics
  EVENTS = {
    "Signup" => "/app/signed-up",
    "Business Created" => "/app/business-created",
    "First Quote Sent" => "/app/first-quote-sent"
  }.freeze

  def self.host = ENV["ANALYTICS_HOST"].to_s.chomp("/").presence
  def self.domain = ENV["ANALYTICS_DOMAIN"].presence
  # config.x.analytics is false in development and test (config/application.rb).
  def self.enabled? = host.present? && domain.present? && Rails.configuration.x.analytics

  # The script tag's source, or nil when analytics is off.
  def self.script_url = enabled? ? "#{host}/js/script.js" : nil

  def self.track(event, request:)
    path = EVENTS.fetch(event)
    return unless enabled?

    AnalyticsEventJob.perform_later(event, "https://#{domain}#{path}", request.user_agent.to_s.first(512), request.remote_ip.to_s)
  end
end
