class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_legal_terms # MKT-03: a material change to the Terms or Privacy is accepted first
  include BusinessContext
  include ConfirmedSender
  before_action :require_business_setup
  include Authorization # after setup, so users without a business are sent to create one
  layout "app"
  before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") } # MKT-04: never in search results
  rescue_from(ClientLink::ClientErased) { redirect_back_or_to admin_root_path, alert: "This client's details were erased, so nothing more can be sent to them." }

  private

  def require_current_legal_terms
    return if current_user.legal_documents_to_accept.none?

    session[:after_legal_acceptance] = request.fullpath if request.get?
    redirect_to legal_acceptance_path
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
