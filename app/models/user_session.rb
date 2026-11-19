# A signed-in browser (ACC-06): what the account page lists as "Chrome on Mac · last active 5
# minutes ago", and what "Sign out" ends. The browser keeps "id:secret" in its session; only a
# digest of the secret is stored. Wired up in config/initializers/user_sessions.rb.
class UserSession < ApplicationRecord
  SESSION_KEY = "user_session" # in the signed-in user's Warden session data
  ACTIVITY_EVERY = 5.minutes # how often last_active_at is written
  LISTED_FOR = 30.days       # sessions idle longer aren't listed (remember-me lasts 4 weeks)
  KEPT_FOR = 90.days         # then they're deleted

  belongs_to :user

  scope :active, -> { where(revoked_at: nil) }
  scope :listed, -> { active.where(last_active_at: LISTED_FOR.ago..).order(last_active_at: :desc) }

  # A new session for this browser; returns [session, "id:secret"] for the browser to keep.
  def self.start!(user, request)
    user.user_sessions.where(last_active_at: ...KEPT_FOR.ago).delete_all
    secret = SecureRandom.base58(32)
    session = user.user_sessions.create!(secret_digest: digest(secret), last_active_at: Time.current, **request_details(request))
    [ session, "#{session.id}:#{secret}" ]
  end

  # The session a browser's "id:secret" belongs to, revoked or not; nil if it doesn't match.
  def self.find_by_credential(user, credential)
    id, secret = credential.to_s.split(":", 2)
    return if id.blank? || secret.blank?

    session = user.user_sessions.find_by(id:)
    session if session && ActiveSupport::SecurityUtils.secure_compare(session.secret_digest, digest(secret))
  end

  def self.digest(secret) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "user-session:#{secret}")

  def self.request_details(request)
    { user_agent: request.user_agent.to_s.first(300).presence, ip_address: request.remote_ip }
  end

  def active? = revoked_at.nil?

  def revoke! = (update_columns(revoked_at: Time.current) if active?)

  # Records that the browser was here (at most every ACTIVITY_EVERY, to keep writes down).
  def seen!(request)
    return if last_active_at > ACTIVITY_EVERY.ago

    update_columns(last_active_at: Time.current, updated_at: Time.current, **self.class.request_details(request))
  end

  # "Chrome on Mac", from the browser's user agent; good enough to recognise your own devices.
  def device_label
    ua = user_agent.to_s
    browser = { /Edg\// => "Edge", /OPR\/|Opera/ => "Opera", /Firefox\// => "Firefox", /Chrome\/|CriOS\// => "Chrome", /Safari\// => "Safari" }
                .find { |pattern, _| ua.match?(pattern) }&.last
    platform = { /iPhone/ => "iPhone", /iPad/ => "iPad", /Android/ => "Android", /Mac OS X|Macintosh/ => "Mac", /Windows/ => "Windows",
                 /CrOS/ => "Chromebook", /Linux/ => "Linux" }.find { |pattern, _| ua.match?(pattern) }&.last
    [ browser || "A browser", platform ].compact.join(" on ")
  end
end
