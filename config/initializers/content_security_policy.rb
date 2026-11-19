# PLT-13: a strict content security policy. Scripts and styles come from our own origin; the
# few inline <style> blocks a page needs (brand colors, calendar positions) carry the request's
# nonce (InlineStyleHelper), and nothing uses inline event handlers or style attributes. Pages
# can't be framed, forms only post to us, and plugins are off.
#
# Third parties are added here deliberately, one at a time, when a feature needs them (Stripe's
# hosted checkout is a redirect, so it only needs form-action once BIL-04 posts to it).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.connect_src :self
    policy.font_src :self, :data
    policy.form_action :self
    policy.frame_ancestors :none
    policy.frame_src :none
    policy.img_src :self, :data, :blob
    policy.manifest_src :self
    policy.media_src :self
    policy.object_src :none
    policy.script_src :self
    policy.style_src :self
    policy.worker_src :self
    policy.report_uri "/csp-reports"
  end

  # The session id is stable across a visit, so <style> blocks arriving with Turbo navigations
  # and streams carry the same nonce as the page they land in. It's never exposed: the session
  # cookie is encrypted.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s.presence || SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
