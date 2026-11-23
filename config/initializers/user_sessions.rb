# ACC-06: every sign-in starts a UserSession for that browser, and coming back through "Keep me
# signed in" resumes the one it remembered while that's still active (#403); each request checks
# it's still active (and notes the activity); signing out ends it. A browser whose session was signed out
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

  # Signs this browser out, deleting its remember-me cookie but leaving remember-me on the
  # user's other browsers alone (Devise's sign-out would cancel it everywhere, #403).
  sign_out_here = lambda do |user, auth|
    user.forget_this_browser_only = true
    auth.logout(:user)
  ensure
    user.forget_this_browser_only = nil
  end

  Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
    next unless tracked.(user, opts) && opts[:store] != false

    request = request_for.(auth)
    # Back through "Keep me signed in": resume the session it remembered, only while that's still
    # active, so a browser signed out from another device can't sign itself back in (#403). Not a
    # new session: tabs reopening at once all carry the same cookies.
    if (remembered = opts[:event] == :authentication && auth.winning_strategy.is_a?(Devise::Strategies::Rememberable))
      credential = request.cookie_jar.encrypted[UserSession::REMEMBER_COOKIE]
      previous = UserSession.find_by_credential(user, credential)
      unless previous&.active?
        sign_out_here.(user, auth)
        if request.controller_instance.try(:public_page?)
          auth.clear_strategies_cache!(scope: :user) # so later current_user calls don't try again
          next
        end

        throw :warden, scope: :user, message: (:session_ended if previous)
      end
      previous.seen!(request)
    else
      credential = UserSession.start!(user, request, browser_id: browser_id_for.(request)).last
    end
    auth.session(:user)[UserSession::SESSION_KEY] = credential
    if remembered || user.remember_me
      request.cookie_jar.encrypted[UserSession::REMEMBER_COOKIE] =
        { value: credential, expires: User.remember_for.from_now, httponly: true, same_site: :lax, secure: Rails.env.production? }
    end
  end

  Warden::Manager.after_set_user only: :fetch do |user, auth, opts|
    next unless tracked.(user, opts)

    if (session = UserSession.find_by_credential(user, auth.session(:user)[UserSession::SESSION_KEY]))&.active?
      session.seen!(request_for.(auth))
    else
      sign_out_here.(user, auth)
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
    request_for.(auth).cookie_jar.delete(UserSession::REMEMBER_COOKIE)
  end
end
