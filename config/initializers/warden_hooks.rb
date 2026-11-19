# PLT-13: signing in starts a new content security policy nonce, so one learned before sign-in
# (from a signed-out page) is no use after it. The id of the session itself is renewed by Devise.
Warden::Manager.after_set_user except: :fetch do |_user, auth, _options|
  auth.request.session.delete(:csp_nonce)
end
