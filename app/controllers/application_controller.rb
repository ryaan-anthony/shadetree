class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  include AbuseProtection
  include ImpersonationSupport # OPS-03

  helper_method :feature?, :current_user_session

  # Pages anyone may open, signed in or not: client links, the request form, the marketing
  # site. A browser whose session was ended elsewhere (ACC-06) is signed out quietly there and
  # still sees the page; staff pages send it to sign in with a note (#317). `only:` limits it to
  # some actions, e.g. sign-up but not the account page (#378), so the class value is true or a
  # list of actions: ask #public_page? (the ended-session hook does).
  class_attribute :public_page, instance_writer: false, default: false
  def self.public_page!(only: nil) = self.public_page = only ? Array(only).map(&:to_s) : true
  def public_page? = public_page == true || (public_page.is_a?(Array) && public_page.include?(action_name))

  # For lookups a page fires in the background (search-as-you-type, duplicate checks): their
  # responses don't write the session cookie. The cookie store rewrites the whole session on
  # every response, so a lookup that finishes after a form submit would otherwise overwrite
  # what the submit stored, such as its flash message.
  def self.leaves_session_alone(**options)
    before_action(**options) { request.session_options[:skip] = true }
  end

  private

  # This browser's session (ACC-06), for the account page.
  def current_user_session
    return unless user_signed_in?

    @current_user_session ||= UserSession.find_by_credential(current_user, warden.session(:user)[UserSession::SESSION_KEY])
  end

  # Release flags for the current business (PLT-11).
  def feature?(name) = Feature.enabled?(name)
end
