# PLT-13: browsers post content security policy violations here. They're logged (truncated) so a
# page the policy breaks, or an injection attempt it stopped, shows up in the logs; nothing is
# stored. Anyone can post, so it's rate limited and never errors.
class CspReportsController < ActionController::API
  MAX_BYTES = 8.kilobytes
  # The legacy report-uri format and the Reporting API's names for the same things.
  FIELDS = %w[document-uri violated-directive effective-directive blocked-uri source-file line-number
              documentURL effectiveDirective blockedURL sourceFile lineNumber].freeze

  include ActionController::RateLimiting
  rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :no_content }

  def create
    body = request.body.read(MAX_BYTES).to_s
    data = JSON.parse(body) rescue nil
    report = data.is_a?(Array) ? data.first&.dig("body") : data&.dig("csp-report") if data.is_a?(Array) || data.is_a?(Hash)
    Rails.logger.warn("[csp] #{report.slice(*FIELDS).to_json.truncate(1_000)}") if report.is_a?(Hash)
    head :no_content
  end
end
