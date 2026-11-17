# CLI-03: a business's public request page, /request/<handle>. No sign-in: anyone can ask for
# work. The handle is the only way in, and everything after it runs as that business.
#
# Spam protection is invisible to people: a field they can't see (bots fill it, and get the
# usual "sent" page with nothing created), a signed timestamp that must be from this page and
# at least a few seconds old, and limits on attempts per IP address (per business) and on
# requests per business. Anything but the hidden field shows the form again, filled in.
class PublicRequestsController < ApplicationController
  layout "client"

  MIN_SECONDS_ON_PAGE = 3
  FORM_LIFETIME = 1.day
  ATTEMPTS_PER_IP = [ 10, 10.minutes ].freeze # per business, so one page's traffic can't block another's
  REQUESTS_PER_HOUR = 60 # per business: requests created, so failed attempts can't use them up

  before_action :load_business
  around_action :as_business

  def new
    @submission = RequestSubmission.new(business: @business)
  end

  def create
    return render(:new, status: :unprocessable_content) unless @business.request_form_enabled?
    # Only bots fill the hidden field: they get the "sent" page and nothing is created.
    return redirect_to(public_request_sent_path(@business.handle)) if params[:website].present?

    @submission = RequestSubmission.new(business: @business, **submission_params)
    if (problem = form_problem || limit_problem)
      @submission.photos = [] # not worth processing for a form that goes back anyway
      @submission.valid?
      @submission.errors.add(:base, problem)
      return render(:new, status: :unprocessable_content)
    end
    saved = @submission.save
    return render(:new, status: :unprocessable_content) unless saved

    redirect_to public_request_sent_path(@business.handle), flash: { emailed: saved.acknowledgment_queued? }
  end

  def sent; end

  private

  def load_business
    @business = Business.active.find_by(handle: params[:handle].to_s.downcase)
    render :not_found, status: :not_found, layout: "client" unless @business
  end

  def as_business(&) = Tenancy.with_business(@business, &)

  # Why the form can't be taken as sent: not from this page, too old, or sent within seconds of
  # opening it (people take longer; scripts don't). Nil when it's fine.
  def form_problem
    started = form_verifier.verified(params[:form_token].to_s, purpose: @business.handle)
    if started.nil? then "This page was open for a while. Check your details and send it again."
    elsif Time.zone.at(started.to_f) > MIN_SECONDS_ON_PAGE.seconds.ago then "Check your details, then send your request."
    end
  end

  # Attempts per IP address on this business's page (in Rails.cache, shared across processes
  # in production), then requests created for the business in the last hour.
  def limit_problem
    limit, period = ATTEMPTS_PER_IP
    attempts = Rails.cache.increment("request-form:#{@business.id}:#{request.remote_ip}", 1, expires_in: period)
    if (attempts && attempts > limit) || ServiceRequest.where(source: "form", created_at: 1.hour.ago..).count >= REQUESTS_PER_HOUR
      "We've had a lot of requests in the last few minutes. Please try again shortly, or call or email instead."
    end
  end

  def form_verifier = Rails.application.message_verifier("request_form")
  helper_method def form_token = form_verifier.generate(Time.current.to_f, purpose: @business.handle, expires_in: FORM_LIFETIME)

  def submission_params
    params.fetch(:request_submission, {}).permit(:name, :email, :phone, :address_line1, :address_line2, :city, :region, :postal_code,
                                                  :description, :timing, service_ids: [], photos: []).to_h.symbolize_keys
  end
end
