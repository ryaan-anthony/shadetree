# PLT-13: browsers post content security policy violations here. They're logged (truncated) so a
# page the policy breaks, or an injection attempt it stopped, shows up in the logs; nothing is
# stored. Anyone can post, so it's rate limited and never errors.
class CspReportsController < ActionController::API
  MAX_BYTES = 8.kilobytes
  # The legacy report-uri format and the Reporting API's names for the same things.
  FIELDS = %w[document-uri violated-directive effective-directive blocked-uri source-file line-number
              documentURL effectiveDirective blockedURL sourceFile lineNumber].freeze

  include ActionController::RateLimiting
  wrap_parameters false # the body is read here, capped, not parsed into params
  rate_limit to: 30, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :no_content }

  def create
    body = request.body.read(MAX_BYTES).to_s
    data = JSON.parse(body) rescue nil # rubocop:disable Style/RescueModifier
    report = case data
    when Array then data.first.is_a?(Hash) ? data.first["body"] : nil
    when Hash then data["csp-report"]
    end
    Rails.logger.warn("[csp] #{redact(report.slice(*FIELDS)).to_json.truncate(1_000)}") if report.is_a?(Hash)
    head :no_content
  end

  private

  # Page addresses as paths only, with anything token-like (client links, invitations) masked.
  def redact(fields)
    fields.transform_values do |value|
      next value unless value.is_a?(String) && value.match?(%r{\Ahttps?://})

      (URI.parse(value).path rescue "") # rubocop:disable Style/RescueModifier
        .gsub(%r{[A-Za-z0-9_-]{20,}}, ":token")
    end
  end
end
