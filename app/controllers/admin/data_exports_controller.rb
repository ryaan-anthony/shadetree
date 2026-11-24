# Your data (INS-02): download any table as CSV, on every plan; every download is logged.
class Admin::DataExportsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :read_only, only: %i[index]
  impersonation :blocked # downloads are logged in the member's name
  requires_permission :export_data
  layout "app"

  def index
    @exports = DataExport.newest_first.includes(:requested_by).limit(20)
    @full = DataExport.where(kind: "full").newest_first.first
    @full&.give_up_if_stale! unless impersonation # OPS-03: support looking writes nothing
  end

  # Starts the full export (or finds the one already being built).
  def create
    DataExport.request_full!(by: current_user)
    redirect_to admin_data_exports_path, notice: "We're putting everything together. We'll let you know when it's ready to download."
  end

  # A part of the full export's zip, while its link lasts. Streamed, so a big file never sits in
  # memory. Each download is logged.
  def show
    export = DataExport.where(kind: "full").find_by_param!(params[:id])
    return redirect_to(admin_data_exports_path, alert: "That download has expired. Make a new one below.") unless export.downloadable?

    part = export.parts[params[:part].to_i.clamp(1, export.parts.size) - 1]
    export.log_download!(by: current_user)
    blob = part.blob
    response.headers["Content-Type"] = "application/zip"
    response.headers["Content-Disposition"] = ActionDispatch::Http::ContentDisposition.format(disposition: "attachment", filename: blob.filename.to_s)
    response.headers["Content-Length"] = blob.byte_size.to_s
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["Last-Modified"] = blob.created_at.httpdate # so Rack::ETag doesn't read the whole body to hash it
    self.response_body = Enumerator.new { |chunks| blob.download { chunks << _1 } }
  end

  def download
    return head(:not_found) unless DataExport::TABLES[params[:table].to_s]&.available?

    csv, filename = DataExport.download!(params[:table], by: current_user)
    response.headers["Cache-Control"] = "private, no-store" # client data shouldn't sit in a browser cache
    send_data csv, filename:, type: "text/csv; charset=utf-8"
  end
end
