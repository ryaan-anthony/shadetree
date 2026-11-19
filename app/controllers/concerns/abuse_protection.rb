# PLT-13: what public endpoints share against abuse.
#
# - too_many_requests: the friendly "slow down" page (or a bare 429 for non-HTML), with
#   Retry-After. Use it as rate_limit's `with:`.
# - Public forms (sign-up, the request form, contact): a field people never see (bots fill it)
#   and a signed timestamp that must come from this form and be a few seconds old, plus
#   attempts per IP address. `form_guard_fields(purpose)` in the view renders both fields.
# - Lockdown, the escalation when bots get past that: `bin/rails security:lockdown HOURS=24`
#   (or FORMS_LOCKDOWN=1) makes public forms wait longer and allow fewer attempts per IP.
module AbuseProtection
  extend ActiveSupport::Concern

  MIN_SECONDS = 3
  LOCKDOWN_MIN_SECONDS = 10
  FORM_LIFETIME = 1.day
  LOCKDOWN_ATTEMPTS = [ 3, 1.hour ].freeze
  LOCKDOWN_KEY = "security:forms-lockdown"
  HONEYPOT = :website

  included do
    helper_method :form_guard_token
  end

  def self.lockdown? = ENV["FORMS_LOCKDOWN"].present? || Rails.cache.read(LOCKDOWN_KEY).present?

  def self.lockdown!(hours:) = Rails.cache.write(LOCKDOWN_KEY, Time.current.to_i, expires_in: hours.to_f.hours)

  def self.lift_lockdown! = Rails.cache.delete(LOCKDOWN_KEY)

  private

  def too_many_requests(retry_after: 60)
    response.set_header("Retry-After", retry_after.to_i.to_s)
    respond_to do |format|
      format.html { render "errors/too_many_requests", layout: "application", status: :too_many_requests }
      format.any { head :too_many_requests }
    end
  end

  def honeypot_filled? = params[HONEYPOT].present?

  def form_guard_token(purpose) = form_guard_verifier.generate(Time.current.to_f, purpose: purpose.to_s, expires_in: FORM_LIFETIME)

  # Why the form can't be taken as sent: not from this form, too old, or sent within seconds of
  # opening it (people take longer; scripts don't). Nil when it's fine.
  def form_guard_problem(purpose)
    started = form_guard_verifier.verified(params[:form_token].to_s, purpose: purpose.to_s)
    wait = AbuseProtection.lockdown? ? LOCKDOWN_MIN_SECONDS : MIN_SECONDS
    if started.nil? then "This page was open for a while. Check your details and send it again."
    elsif Time.zone.at(started.to_f) > wait.seconds.ago then "Check your details, then send it again."
    end
  end

  # Counts an attempt from this IP address; true when it's over the limit (tighter in lockdown).
  def too_many_attempts?(key, limit:, within:)
    limit, within = LOCKDOWN_ATTEMPTS if AbuseProtection.lockdown?
    attempts = Rails.cache.increment("attempts:#{key}:#{request.remote_ip}", 1, expires_in: within)
    attempts.to_i > limit
  end

  def form_guard_verifier = Rails.application.message_verifier("form_guard")
end
