require "net/http"

# MKT-04: sends one funnel event to Plausible's events API. Analytics never gets in the way of
# the app: a network failure or a refusal is logged and dropped, never retried into a backlog.
class AnalyticsEventJob < ApplicationJob
  queue_as :default
  self.log_arguments = false # the visitor's IP and browser stay out of the logs
  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError ].freeze
  discard_on(*NETWORK_ERRORS) do |job, error|
    Rails.logger.warn("[analytics] #{job.arguments.first} not sent: #{error.class}: #{error.message}")
  end

  def perform(event, url, user_agent, ip)
    uri = URI("#{Analytics.host}/api/event")
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "User-Agent" => user_agent.presence || "Shadetree",
                                       "X-Forwarded-For" => ip)
    request.body = { name: event, url:, domain: Analytics.domain }.to_json
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 3) { _1.request(request) }
    Rails.logger.warn("[analytics] #{event} refused: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  end
end
