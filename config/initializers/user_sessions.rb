# ACC-06: every sign-in starts a UserSession for that browser; each request checks it's still
# active (and notes the activity); signing out ends it. A browser whose session was signed out
# from another device is signed out on its next request.
Rails.application.config.after_initialize do
  tracked = ->(user, opts) { opts[:scope] == :user && user.is_a?(User) }
  request_for = ->(auth) { ActionDispatch::Request.new(auth.env) }

  Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
    next unless tracked.(user, opts) && opts[:store] != false

    auth.session(:user)[UserSession::SESSION_KEY] = UserSession.start!(user, request_for.(auth)).last
  end

  Warden::Manager.after_set_user only: :fetch do |user, auth, opts|
    next unless tracked.(user, opts)

    credential = auth.session(:user)[UserSession::SESSION_KEY]
    if credential.nil? # signed in before sessions were tracked
      auth.session(:user)[UserSession::SESSION_KEY] = UserSession.start!(user, request_for.(auth)).last
    elsif (session = UserSession.find_by_credential(user, credential))&.active?
      session.seen!(request_for.(auth))
    else
      auth.logout(:user)
      throw :warden, scope: :user, message: :session_ended
    end
  end

  Warden::Manager.before_logout do |user, auth, opts|
    next unless tracked.(user, opts)

    # Read straight from the raw session: asking Warden would fetch the user again, and land back here.
    credential = auth.raw_session["warden.user.user.session"]&.dig(UserSession::SESSION_KEY)
    UserSession.find_by_credential(user, credential)&.revoke! if credential
  end
end
