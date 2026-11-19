class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_legal_terms # MKT-03: a material change to the Terms or Privacy is accepted first
  include BusinessContext
  include ConfirmedSender
  include LocationFilter # CAT-07
  before_action :require_business_setup
  before_action :refuse_suspended_business # OPS-04
  include Authorization # after setup, so users without a business are sent to create one
  layout "app"
  before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") } # MKT-04: never in search results
  rescue_from(ClientLink::ClientErased) { redirect_back_or_to admin_root_path, alert: "This client's details were erased, so nothing more can be sent to them." }

  private

  def require_current_legal_terms
    return if impersonation || current_user.legal_documents_to_accept.none? # OPS-03: support can't accept for them

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

  # CAT-07: a location picked on a document form, if it's one new work can go to.
  def picked_location(uid) = (Location.active.find_by(uid: uid.to_s) if uid.present?)

  # A suspended business's members see who to contact, and can still switch to another business.
  def refuse_suspended_business
    return unless current_business&.suspended?
    return if controller_path == "admin/businesses" && %w[switch new create].include?(action_name)

    render "admin/suspended", status: :forbidden
  end

  # Staff pages need a current business; without one, send the user to create it.
  def require_business_setup
    redirect_to new_admin_business_path unless current_business
  end
end
