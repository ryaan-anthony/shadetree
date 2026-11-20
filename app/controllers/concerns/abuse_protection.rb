# PLT-13: what public endpoints share against abuse.
#
# - too_many_requests: the friendly "slow down" page (or a bare 429 for non-HTML), with
#   Retry-After. Use it as rate_limit's `with:`.
# - Public forms (sign-up, the request form, contact): a field people never see (bots fill it)
#   and a signed timestamp that must come from this form, be a few seconds old, and be used
#   once, plus attempts per IP address. `render "shared/form_guard", purpose:` in the view
#   renders both fields; a form shown again after a problem keeps its original start time, so
#   fixing a typo quickly isn't mistaken for a bot. Rejections are logged ("[abuse] …").
# - Lockdown, the escalation when bots get past that: `bin/rails security:lockdown HOURS=24`
#   (or FORMS_LOCKDOWN=true) makes public forms wait longer and allow fewer attempts per IP.
#   It's kept in the cache, so clearing the cache ends it early.
module AbuseProtection
  extend ActiveSupport::Concern

  MIN_SECONDS = 3
  LOCKDOWN_MIN_SECONDS = 10
  FORM_LIFETIME = 1.day
  LOCKDOWN_ATTEMPTS = [ 5, 15.minutes ].freeze
  LOCKDOWN_KEY = "security:forms-lockdown"
  HONEYPOT = :website
  PROBLEMS = {
    expired: "This page was open for a while. Check your details and send it again.",
    too_fast: "Check your details, then send it again.",
    reused: "Check your details, then send it again."
  }.freeze

  included do
    helper_method :form_guard_token
  end

  def self.lockdown? = ActiveModel::Type::Boolean.new.cast(ENV["FORMS_LOCKDOWN"].presence) || Rails.cache.read(LOCKDOWN_KEY).present?

  def self.lockdown!(hours:) = Rails.cache.write(LOCKDOWN_KEY, Time.current.to_i, expires_in: hours.to_f.hours)

  def self.lift_lockdown! = Rails.cache.delete(LOCKDOWN_KEY)

  private

  # retry_after: the rate limit's window, in seconds.
  def too_many_requests(retry_after: 60)
    @retry_after = retry_after.to_i
    @try_again_url = request.get? || request.head? ? request.fullpath : url_from(request.referer)
    response.set_header("Retry-After", @retry_after.to_s)
    log_abuse("rate limited")
    respond_to do |format|
      format.html { render "errors/too_many_requests", layout: "application", status: :too_many_requests }
      format.any { head :too_many_requests }
    end
  end

  def honeypot_filled?
    filled = params[HONEYPOT].present?
    log_abuse("hidden field filled") if filled
    filled
  end

  # A token for this form, carrying when it was first shown (kept across a re-render).
  def form_guard_token(purpose)
    form_guard_verifier.generate(@form_guard_started || Time.current.to_f, purpose: purpose.to_s, expires_in: FORM_LIFETIME)
  end

  # Why the form can't be taken as sent (:expired, :too_fast or :reused, see PROBLEMS), or nil.
  # A token that passes is used up.
  def form_guard_problem(purpose)
    token = params[:form_token].to_s
    started = form_guard_verifier.verified(token, purpose: purpose.to_s)
    return log_abuse("form expired or forged", purpose:) && :expired if started.nil?

    @form_guard_started = started.to_f
    wait = AbuseProtection.lockdown? ? LOCKDOWN_MIN_SECONDS : MIN_SECONDS
    return log_abuse("form sent too fast", purpose:) && :too_fast if Time.zone.at(started.to_f) > wait.seconds.ago
    return log_abuse("form token reused", purpose:) && :reused unless Rails.cache.write("form-token:#{Digest::SHA256.hexdigest(token)}", 1, unless_exist: true, expires_in: FORM_LIFETIME)

    nil
  end

  # Counts an attempt from this IP address; true when it's over the limit (tighter in lockdown).
  def too_many_attempts?(key, limit:, within:)
    limit, within = LOCKDOWN_ATTEMPTS if AbuseProtection.lockdown?
    over = Rails.cache.increment("attempts:#{key}:#{request.remote_ip}", 1, expires_in: within).to_i > limit
    log_abuse("too many attempts", key:) if over
    over
  end

  def log_abuse(what, **details)
    # The IP is logged on purpose (abuse investigation); link tokens in the path are not (PLT-10).
    Rails.logger.info("[abuse] #{what} #{details.merge(path: SecretPathLogger.redact(request.path), ip: request.remote_ip).to_json}")
    true
  end

  def form_guard_verifier = Rails.application.message_verifier("form_guard")
end
