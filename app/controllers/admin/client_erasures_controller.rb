# Erasing a client's personal data at their request (INS-02), with their name typed to confirm.
class Admin::ClientErasuresController < Admin::BaseController
  requires_permission :export_data
  before_action :set_client
  layout "app"

  def new
    redirect_to admin_client_path(@client), alert: "Their details are already erased." if @client.erased?
  end

  def create
    unless params[:confirmation].to_s.squish.casecmp?(@client.display_name.squish)
      @error = "Type #{@client.display_name} exactly to confirm."
      return render(:new, status: :unprocessable_content)
    end

    ClientErasure.new(@client, by: current_user).erase!
    redirect_to admin_client_path(@client), notice: "Their details are erased. Documents and payments stay, under “Erased client”."
  end

  private

  def set_client = @client = Client.find_by_param!(params[:client_id])
end
