class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_legal_terms # MKT-03: a material change to the Terms or Privacy is accepted first
  include BusinessContext
  include ConfirmedSender
  before_action :require_business_setup
  include Authorization # after setup, so users without a business are sent to create one
  layout "app"
  before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") } # MKT-04: never in search results

  private

  def require_current_legal_terms
    return if current_user.legal_documents_to_accept.none?

    # Lookups and frames get a plain refusal (and no session write); only a full page is worth
    # returning to after accepting.
    return head(:forbidden) unless request.format.html? && !turbo_frame_request? && !request.xhr?

    session[:after_legal_acceptance] = request.fullpath if request.get? || request.head?
    redirect_to legal_acceptance_path, status: :see_other
  end

  # ACC-05: a page opened from the setup checklist (from=setup) goes back to it when done.
  helper_method def from_setup? = params[:from] == "setup"

  def redirect_after_setup_step(default, **options)
    redirect_to(from_setup? ? admin_root_path : default, **options)
  end

  # Staff pages need a current business; without one, send the user to create it.
  def require_business_setup
    redirect_to new_admin_business_path unless current_business
  end
end
