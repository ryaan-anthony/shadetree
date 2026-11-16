# CLI-03: a business's public request page, /request/<handle>. No sign-in: anyone can ask for
# work. The handle is the only way in, and everything after it runs as that business.
#
# Spam protection is invisible to people: a field they can't see (bots fill it, and get the
# usual "sent" page with nothing created), a signed timestamp that must be from this page and
# at least a few seconds old (otherwise the form is shown again, filled in), and rate limits
# per IP address and per business.
class PublicRequestsController < ApplicationController
  layout "client"

  MIN_SECONDS_ON_PAGE = 3
  FORM_LIFETIME = 1.day

  PER_IP = [ 5, 10.minutes ].freeze
  PER_BUSINESS = [ 60, 1.hour ].freeze

  before_action :load_business
  before_action :within_limits, only: :create
  around_action :as_business

  def new
    @submission = RequestSubmission.new(business: @business)
  end

  def create
    return render(:new, status: :unprocessable_content) unless @business.request_form_enabled?
    # Only bots fill the hidden field: they get the "sent" page and nothing is created.
    return redirect_to(public_request_sent_path(@business.handle)) if params[:website].present?

    @submission = RequestSubmission.new(business: @business, **submission_params)
    return render(:new, status: :unprocessable_content) unless @submission.valid? && fresh_form?
    return render(:new, status: :unprocessable_content) unless @submission.save

    redirect_to public_request_sent_path(@business.handle), flash: { emailed: @submission.email.present? }
  end

  def sent; end

  private

  def load_business
    @business = Business.active.find_by(handle: params[:handle].to_s.downcase)
    render :not_found, status: :not_found, layout: "client" unless @business
  end

  def as_business(&) = Tenancy.with_business(@business, &)

  # Submissions per IP address and per business, counted in Rails.cache (shared across
  # processes in production).
  def within_limits
    limited = { "ip:#{request.remote_ip}" => PER_IP, "business:#{@business.id}" => PER_BUSINESS }.any? do |key, (limit, period)|
      count = Rails.cache.increment("request-form:#{key}", 1, expires_in: period)
      count && count > limit
    end
    render :limited, status: :too_many_requests if limited
  end

  # The form must have been shown by us, within a day, and more than a few seconds ago. A
  # person who trips this (autofill and a quick tap) sees the form again, filled in, to send.
  def fresh_form?
    started = form_verifier.verified(params[:form_token].to_s, purpose: @business.handle)
    message = if started.nil? then "This page was open for a while. Check your details and send it again."
    elsif Time.zone.at(started.to_f) > MIN_SECONDS_ON_PAGE.seconds.ago then "Check your details, then send your request."
    end
    @submission.errors.add(:base, message) if message
    message.nil?
  end

  def form_verifier = Rails.application.message_verifier("request_form")
  helper_method def form_token = form_verifier.generate(Time.current.to_f, purpose: @business.handle, expires_in: FORM_LIFETIME)

  def submission_params
    params.fetch(:request_submission, {}).permit(:name, :email, :phone, :address_line1, :address_line2, :city, :region, :postal_code,
                                                  :description, :timing, service_ids: [], photos: []).to_h.symbolize_keys
  end
end
