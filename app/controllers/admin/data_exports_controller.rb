# Your data (INS-02): download any table as CSV, on every plan; every download is logged.
class Admin::DataExportsController < Admin::BaseController
  requires_permission :export_data
  layout "app"

  def index
    @exports = DataExport.newest_first.includes(:requested_by).limit(20)
    @full = DataExport.where(kind: "full", status: %w[building ready]).newest_first.first
  end

  # Starts the full export (or finds the one already being built).
  def create
    DataExport.request_full!(by: current_user)
    redirect_to admin_data_exports_path, notice: "We're putting everything together. We'll let you know when it's ready to download."
  end

  # The full export's zip, while its link lasts. Streamed, so a big file never sits in memory.
  def show
    export = DataExport.where(kind: "full").find_by_param!(params[:id])
    return redirect_to(admin_data_exports_path, alert: "That download has expired. Make a new one below.") unless export.downloadable?

    blob = export.file.blob
    response.headers["Content-Type"] = "application/zip"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: blob.filename.to_s)
    response.headers["Content-Length"] = blob.byte_size.to_s
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Last-Modified"] = blob.created_at.httpdate # so Rack::ETag doesn't read the whole body to hash it
    self.response_body = Enumerator.new { |chunks| blob.download { chunks << _1 } }
  end

  def download
    return head(:not_found) unless DataExport::TABLES.key?(params[:table])

    csv, filename = DataExport.download!(params[:table], by: current_user)
    response.headers["Cache-Control"] = "private, no-store" # client data shouldn't sit in a browser cache
    send_data csv, filename:, type: "text/csv; charset=utf-8"
  end
end
