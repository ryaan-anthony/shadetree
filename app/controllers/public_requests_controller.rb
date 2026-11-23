# CLI-03: a business's public request page, /request/<handle>. No sign-in: anyone can ask for
# work. The handle is the only way in, and everything after it runs as that business.
#
# Spam protection is invisible to people (AbuseProtection, PLT-13): a field they can't see
# (bots fill it, and get the usual "sent" page with nothing created), a signed timestamp that
# must be from this page and at least a few seconds old, and limits on attempts per IP address
# (per business) and on requests per business. Anything but the hidden field shows the form
# again, filled in.
class PublicRequestsController < ApplicationController
  public_page!
  layout "client"

  ATTEMPTS_PER_IP = [ 10, 10.minutes ].freeze # per business, so one page's traffic can't block another's
  REQUESTS_PER_HOUR = 60 # per business: requests created, so failed attempts can't use them up

  before_action :load_business
  around_action :as_business

  def new
    @submission = RequestSubmission.new(business: @business, location: params[:location].presence)
    @submission.location = nil unless @submission.chosen_location # an old link to an archived location: let them choose
    @contact = @submission.chosen_location
  end

  def create
    return render(:new, status: :unprocessable_content) unless @business.request_form_enabled?
    # Only bots fill the hidden field: they get the "sent" page and nothing is created.
    return redirect_to(public_request_sent_path(@business.handle)) if honeypot_filled?

    @submission = RequestSubmission.new(business: @business, **submission_params)
    @contact = @submission.chosen_location
    if (problem = AbuseProtection::PROBLEMS[form_guard_problem(form_purpose)] || limit_problem)
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

  helper_method def form_purpose = "request:#{@business.handle}"

  # Attempts per IP address on this business's page (in Rails.cache, shared across processes
  # in production), then requests created for the business in the last hour.
  def limit_problem
    limit, within = ATTEMPTS_PER_IP
    if too_many_attempts?("request-form:#{@business.id}", limit:, within:) || ServiceRequest.where(source: "form", created_at: 1.hour.ago..).count >= REQUESTS_PER_HOUR
      "We've had a lot of requests in the last few minutes. Please try again shortly, or call or email instead."
    end
  end

  def submission_params
    params.fetch(:request_submission, {}).permit(:name, :email, :phone, :address_line1, :address_line2, :city, :region, :postal_code,
                                                  :description, :timing, :location, service_ids: [], photos: []).to_h.symbolize_keys
  end
end
