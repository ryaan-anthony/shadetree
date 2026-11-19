# MKT-03: accepting a material change to the Terms or Privacy Policy, asked on the next visit
# to the app after it takes effect (Admin::BaseController#require_current_legal_terms).
class Users::LegalAcceptancesController < ApplicationController
  before_action :authenticate_user!
  layout "application"

  def show
    @documents = current_user.legal_documents_to_accept
    redirect_to admin_root_path if @documents.none?
  end

  def create
    @documents = current_user.legal_documents_to_accept
    unless params[:accept] == "1"
      flash.now[:alert] = "Tick the box to accept, or sign out if you don't."
      return render(:show, status: :unprocessable_content)
    end

    current_user.accept_legal_terms!
    redirect_to url_from(session.delete(:after_legal_acceptance)) || admin_root_path, notice: "Thanks. You're all set."
  end
end
