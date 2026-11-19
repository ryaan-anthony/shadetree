# PLT-13: response headers and the session cookie, on top of Rails' defaults (nosniff,
# strict-origin-when-cross-origin referrers, no cross-domain policies). HSTS comes from
# force_ssl in production (two years, subdomains included).
Rails.application.config.action_dispatch.default_headers.merge!(
  "Cross-Origin-Opener-Policy" => "same-origin",
  "Referrer-Policy" => "strict-origin-when-cross-origin",
  # Nothing in the app uses these, so no page (or anything injected into one) can ask for them.
  # Photo uploads use a file input, which needs no camera permission. (Rails' permissions_policy
  # still sends the old Feature-Policy header, which browsers ignore.)
  "Permissions-Policy" => "camera=(), microphone=(), geolocation=(), usb=(), payment=(), gyroscope=(), " \
                          "magnetometer=(), accelerometer=(), fullscreen=(self)"
)

# The session cookie: HTTP-only, same-site lax (links from emails still arrive signed in), and
# secure wherever we serve HTTPS. Devise renews the session id on sign-in, so a session fixed
# before sign-in is useless after it.
Rails.application.config.session_store :cookie_store,
  key: "_shadetree_session",
  httponly: true,
  same_site: :lax,
  secure: Rails.env.production?
