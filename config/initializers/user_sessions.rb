# ACC-06: every sign-in starts a UserSession for that browser; each request checks it's still
# active (and notes the activity); signing out ends it. A browser whose session was signed out
# from another device is signed out on its next request, and so is one with no session at all
# (there's no other way to sign it out later). Staff pages then send it to sign in with a note;
# public pages (ApplicationController.public_page) just show, signed out (#317).
Rails.application.config.after_initialize do
  tracked = ->(user, opts) { opts[:scope] == :user && user.is_a?(User) }
  request_for = ->(auth) { ActionDispatch::Request.new(auth.env) }
  credential_in = ->(auth) { auth.raw_session["warden.user.user.session"]&.dig(UserSession::SESSION_KEY) }

  # A permanent id for this browser, so signing in again here replaces its old session.
  browser_id_for = lambda do |request|
    cookies = request.cookie_jar
    cookies.signed[UserSession::BROWSER_COOKIE] ||
      SecureRandom.base58(24).tap { cookies.signed.permanent[UserSession::BROWSER_COOKIE] = { value: _1, httponly: true, same_site: :lax, secure: Rails.env.production? } }
  end

  Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
    next unless tracked.(user, opts) && opts[:store] != false

    request = request_for.(auth)
    auth.session(:user)[UserSession::SESSION_KEY] = UserSession.start!(user, request, browser_id: browser_id_for.(request)).last
  end

  Warden::Manager.after_set_user only: :fetch do |user, auth, opts|
    next unless tracked.(user, opts)

    if (session = UserSession.find_by_credential(user, auth.session(:user)[UserSession::SESSION_KEY]))&.active?
      session.seen!(request_for.(auth))
    else
      auth.logout(:user)
      # Public pages (client links, the request form, marketing) still show, signed out (#317).
      next if request_for.(auth).controller_instance.try(:public_page?)

      throw :warden, scope: :user, message: :session_ended
    end
  end

  # Devise turned the session away (a password reset or "sign out everywhere" elsewhere changed
  # the account): end it in the list too.
  Warden::Manager.after_failed_fetch do |_user, auth, opts|
    next unless opts[:scope] == :user && (credential = credential_in.(auth))

    UserSession.find_by_credential(nil, credential)&.revoke!
  end

  Warden::Manager.before_logout do |user, auth, opts|
    next unless tracked.(user, opts)

    # Read straight from the raw session: asking Warden would fetch the user again, and land back here.
    credential = credential_in.(auth)
    UserSession.find_by_credential(user, credential)&.revoke! if credential
  end
end
