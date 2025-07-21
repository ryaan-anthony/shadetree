# Feature: Quote & Invoice Export

## Overview
Enable businesses to export quote and invoice data in standard formats (CSV, PDF) for accounting software integration, backup purposes, and external analysis.

## User Stories
- As a business owner, I want to export my quotes to CSV so I can analyze them in Excel
- As an accountant, I want to export invoice data for tax preparation and bookkeeping
- As a business owner, I want PDF exports for professional record keeping

## Tasks

### 1. Create DataExport Model
**File**: `app/models/data_export.rb`

**Implementation Notes**:
```ruby
class DataExport < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  has_one_attached :export_file
  
  validates :export_type, :format, :status, presence: true
  validates :parameters, presence: true
  
  enum export_type: {
    quotes: 0,
    invoices: 1,
    contacts: 2,
    jobs: 3,
    payments: 4,
    custom: 5
  }
  
  enum format: { csv: 0, pdf: 1, excel: 2 }
  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }
  
  scope :recent, -> { where(created_at: 7.days.ago..) }
  scope :completed, -> { where(status: 'completed') }
  
  def file_path
    "exports/#{business_id}/#{id}.#{format}"
  end
  
  def download_url
    Rails.application.routes.url_helpers.rails_blob_path(
      export_file, disposition: 'attachment'
    ) if export_file.attached?
  end
  
  def estimated_completion
    return nil unless processing?
    created_at + 5.minutes # Simple estimation
  end
end
```

### 2. Create QuoteInvoiceExportService
**File**: `app/services/quote_invoice_export_service.rb`

**Implementation Notes**:
```ruby
class QuoteInvoiceExportService
  def initialize(business, export_type, format, parameters = {})
    @business = business
    @export_type = export_type
    @format = format
    @parameters = parameters
  end
  
  def generate
    case @export_type
    when 'quotes'
      export_quotes
    when 'invoices'
      export_invoices
    else
      raise "Unsupported export type: #{@export_type}"
    end
  end
  
  private
  
  def export_quotes
    quotes = @business.quotes.includes(:client, :quote_line_items)
    quotes = apply_filters(quotes)
    
    case @format
    when 'csv'
      generate_quotes_csv(quotes)
    when 'pdf'
      generate_quotes_pdf(quotes)
    when 'excel'
      generate_quotes_excel(quotes)
    end
  end
  
  def export_invoices
    quotes = @business.quotes.accepted.includes(:client, :quote_line_items)
    quotes = apply_filters(quotes)
    
    case @format
    when 'csv'
      generate_invoices_csv(quotes)
    when 'pdf'
      generate_invoices_pdf(quotes)
    end
  end
  
  def apply_filters(relation)
    relation = relation.where(created_at: date_range) if @parameters[:date_range]
    relation = relation.where(status: @parameters[:status]) if @parameters[:status]
    relation = relation.where(client_id: @parameters[:client_ids]) if @parameters[:client_ids]
    relation
  end
  
  def date_range
    case @parameters[:date_range]
    when 'this_month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'last_month'
      1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when 'this_year'
      Date.current.beginning_of_year..Date.current.end_of_year
    when 'custom'
      Date.parse(@parameters[:start_date])..Date.parse(@parameters[:end_date])
    else
      nil
    end
  end
  
  def generate_quotes_csv(quotes)
    CSV.generate(headers: true) do |csv|
      csv << [
        'Quote ID',
        'Client Name',
        'Client Email',
        'Date Created',
        'Status',
        'Total Amount',
        'Services',
        'Notes',
        'Due Date',
        'Payment Status'
      ]
      
      quotes.each do |quote|
        csv << [
          quote.id,
          quote.client.name,
          quote.client.email,
          quote.created_at.strftime('%Y-%m-%d'),
          quote.status.humanize,
          quote.total_amount,
          quote.quote_line_items.map(&:service_name).join('; '),
          quote.notes,
          quote.due_date&.strftime('%Y-%m-%d'),
          quote.payment_status&.humanize
        ]
      end
    end
  end
  
  def generate_quotes_pdf(quotes)
    pdf = Prawn::Document.new
    
    pdf.text "Quote Export - #{@business.name}", size: 20, style: :bold
    pdf.text "Generated: #{Date.current.strftime('%B %d, %Y')}", size: 12
    pdf.move_down 20
    
    table_data = [['Quote ID', 'Client', 'Date', 'Status', 'Amount']]
    
    quotes.each do |quote|
      table_data << [
        quote.id.to_s,
        quote.client.name,
        quote.created_at.strftime('%m/%d/%Y'),
        quote.status.humanize,
        "$#{quote.total_amount}"
      ]
    end
    
    pdf.table(table_data, header: true, width: pdf.bounds.width) do
      row(0).font_style = :bold
      columns(4).align = :right
    end
    
    pdf.render
  end
end
```

### 3. Create DataExportsController
**File**: `app/controllers/admin/data_exports_controller.rb`

**Implementation Notes**:
```ruby
class Admin::DataExportsController < Admin::BaseController
  before_action :set_data_export, only: [:show, :download, :destroy]
  before_action :ensure_can_export_data
  
  def index
    @exports = current_business.data_exports
      .includes(:created_by)
      .order(created_at: :desc)
      .page(params[:page])
  end
  
  def new
    @export_types = export_type_options
    @formats = format_options
    @date_ranges = date_range_options
  end
  
  def create
    @export = current_business.data_exports.build(export_params)
    @export.created_by = current_user
    @export.status = :pending
    
    if @export.save
      DataExportJob.perform_later(@export.id)
      redirect_to admin_data_exports_path, notice: 'Export started. You will receive an email when complete.'
    else
      @export_types = export_type_options
      @formats = format_options
      @date_ranges = date_range_options
      render :new, status: :unprocessable_entity
    end
  end
  
  def show
    @export_details = JSON.parse(@export.parameters) rescue {}
  end
  
  def download
    if @export.completed? && @export.export_file.attached?
      redirect_to @export.download_url
    else
      redirect_to admin_data_exports_path, alert: 'Export not ready for download.'
    end
  end
  
  def destroy
    @export.destroy
    redirect_to admin_data_exports_path, notice: 'Export deleted successfully.'
  end
  
  private
  
  def set_data_export
    @export = current_business.data_exports.find(params[:id])
  end
  
  def export_params
    params.require(:data_export).permit(
      :export_type, :format, 
      parameters: [:date_range, :start_date, :end_date, :status, client_ids: []]
    )
  end
  
  def export_type_options
    [
      ['Quotes', 'quotes'],
      ['Invoices', 'invoices'],
      ['Contacts', 'contacts'],
      ['Jobs', 'jobs'],
      ['Payments', 'payments']
    ]
  end
  
  def format_options
    [
      ['CSV', 'csv'],
      ['PDF', 'pdf'],
      ['Excel', 'excel']
    ]
  end
  
  def date_range_options
    [
      ['This Month', 'this_month'],
      ['Last Month', 'last_month'],
      ['This Year', 'this_year'],
      ['Custom Range', 'custom']
    ]
  end
  
  def ensure_can_export_data
    unless current_business_user.can_view_business_settings?
      redirect_to admin_dashboard_path, alert: 'Access denied'
    end
  end
end
```

## Acceptance Criteria
- Quotes and invoices can be exported in CSV, PDF, and Excel formats
- Export filters work for date ranges, status, and specific clients
- Large exports are processed in background jobs
- Export status is tracked and users are notified when complete
- Exported files can be downloaded securely with expiration
- Export history is maintained for audit purposes

## Estimate
- Story Points: 10
- Timeline: 1 week
- Dependencies: Background job system, file storage, PDF generation
