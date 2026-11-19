class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include AbuseProtection

  helper_method :feature?, :current_user_session

  # For lookups a page fires in the background (search-as-you-type, duplicate checks): their
  # responses don't write the session cookie. The cookie store rewrites the whole session on
  # every response, so a lookup that finishes after a form submit would otherwise overwrite
  # what the submit stored, such as its flash message.
  def self.leaves_session_alone(**options)
    before_action(**options) { request.session_options[:skip] = true }
  end

  # Turbo prefetches a link's page on hover (marked X-Sec-Purpose: prefetch). Those requests only
  # read, so they leave the session alone too: one finishing after a click's request would wipe
  # its flash (the schedule's "Put back" after Undo was lost this way).
  before_action { request.session_options[:skip] = true if request.headers["X-Sec-Purpose"] == "prefetch" }

  private

  # This browser's session (ACC-06), for the account page.
  def current_user_session
    return unless user_signed_in?

    @current_user_session ||= UserSession.find_by_credential(current_user, warden.session(:user)[UserSession::SESSION_KEY])
  end

  # Release flags for the current business (PLT-11).
  def feature?(name) = Feature.enabled?(name)
end
