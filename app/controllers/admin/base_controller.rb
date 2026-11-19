class Admin::BaseController < ApplicationController
  before_action :authenticate_user!
  include BusinessContext
  include ConfirmedSender
  before_action :require_business_setup
  include Authorization # after setup, so users without a business are sent to create one
  layout "app"
  before_action { response.set_header("X-Robots-Tag", "noindex, nofollow") } # MKT-04: never in search results

  private

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
