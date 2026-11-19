# Your data (INS-02): download any table as CSV, on every plan; every download is logged.
class Admin::DataExportsController < Admin::BaseController
  requires_permission :export_data
  layout "app"

  def index
    @exports = DataExport.newest_first.includes(:requested_by).limit(20)
  end

  def download
    return head(:not_found) unless DataExport::TABLES.key?(params[:table])

    csv, filename = DataExport.download!(params[:table], by: current_user)
    response.headers["Cache-Control"] = "private, no-store" # client data shouldn't sit in a browser cache
    send_data csv, filename:, type: "text/csv; charset=utf-8"
  end
end
