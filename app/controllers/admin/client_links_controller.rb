# Staff tools for client links: preview as the client sees it, revoke, and re-issue (PLT-12).
class Admin::ClientLinksController < Admin::BaseController
  requires_permission :office # owners and admins; technicians get 403 (ACC-04)
  before_action :set_client_link

  # The client page with a preview banner. Not counted as a client view.
  def preview
    @preview = true
    @document = @client_link.linkable
    @business = current_business
    render "client_links/show", layout: "client"
  end

  def revoke
    @client_link.revoke!(by: current_user)
    redirect_back_or_to admin_root_path, notice: "Link revoked. The client will see that it's no longer active."
  end

  def reissue
    new_link = @client_link.reissue!(by: current_user)
    redirect_back_or_to admin_root_path, notice: "New link created. The old one no longer works.",
                                         flash: { client_link_url: client_link_url(new_link.token) }
  end

  private

  def set_client_link
    @client_link = ClientLink.find_by_param!(params[:id])
  end
end
