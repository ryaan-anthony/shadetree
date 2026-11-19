require "csv"

# Client CSV import (CLI-06): upload, map columns with a preview, then import in the background.
class Admin::ClientImportsController < Admin::BaseController
  # OPS-03: what support may do while viewing as a member
  impersonation :allowed
  requires_permission :office
  before_action :set_import, only: %i[show edit update report undo]
  layout "app"

  TEMPLATE_HEADERS = [ "Name", "Company", "Email", "Phone", "Street address", "Address line 2", "City", "State", "ZIP", "Notes", "Tags" ].freeze
  TEMPLATE_ROW = [ "Maria Lopez", "", "maria@example.com", "(555) 010-0100", "12 Elm St", "", "Asheville", "NC", "28801", "Gate code 4411", "weekly, residential" ].freeze

  def new
    @recent = ClientImport.order(created_at: :desc).limit(5)
  end

  def create
    return redirect_to(new_admin_client_import_path, alert: "Choose a CSV file to upload.") unless params[:file].respond_to?(:read)
    # Checked before reading, so a huge upload never fills memory.
    return redirect_to(new_admin_client_import_path, alert: "The file is larger than #{ClientImport::CsvFile::MAX_BYTES / 1.megabyte} MB. Split it into smaller files.") if params[:file].size > ClientImport::CsvFile::MAX_BYTES

    import = ClientImport.start!(params[:file], by: current_user)
    wide = import.headers.size >= ClientImport::CsvFile::MAX_COLUMNS
    redirect_to edit_admin_client_import_path(import), notice: ("Only the first #{ClientImport::CsvFile::MAX_COLUMNS} columns are used." if wide)
  rescue ClientImport::CsvFile::Invalid => error
    redirect_to new_admin_client_import_path, alert: error.message
  end

  # Mapping, duplicates and the preview. A changed mapping re-renders the preview first.
  def edit
    redirect_to(admin_client_import_path(@import)) unless @import.mapping?
  end

  def update
    return redirect_to(admin_client_import_path(@import)) unless @import.mapping?

    @import.assign_attributes(mapping: mapping_param, duplicates: params.dig(:client_import, :duplicates).presence || @import.duplicates)
    return render(:edit, status: :unprocessable_content) unless @import.save
    return redirect_to(edit_admin_client_import_path(@import)) unless params[:start]

    @import.start!
    redirect_to admin_client_import_path(@import)
  end

  # Progress while it runs (the page refreshes itself), then the summary.
  def show
    redirect_to(edit_admin_client_import_path(@import)) if @import.mapping?
  end

  # The rows that didn't go in, and why, as a CSV to fix and upload again.
  def report
    send_data @import.report_csv, filename: "#{File.basename(@import.filename, ".*")}-not-imported.csv", type: "text/csv"
  end

  def undo
    if @import.undo!
      redirect_to admin_client_import_path(@import), notice: "Removing the clients this import added."
    else
      redirect_to admin_client_import_path(@import), alert: "This import can't be undone any more."
    end
  end

  def template
    csv = CSV.generate { |rows| rows << TEMPLATE_HEADERS << TEMPLATE_ROW }
    send_data csv, filename: "shadetree-clients-template.csv", type: "text/csv"
  end

  private

  def set_import = @import = ClientImport.find_by_param!(params[:id])

  # { "0" => "display_name", ... } from one select per column; blank means "don't import".
  def mapping_param
    columns = params.fetch(:client_import, {}).fetch(:columns, {}).permit(*@import.headers.each_index.map(&:to_s))
    columns.to_h.select { |_, field| ClientImport::FIELDS.key?(field) }
  end
end
