# Epic: Data Export

## Overview
Enable business owners to export their data in standard formats (CSV, PDF) for quotes, jobs, contacts, and other business records. Support accounting software integration, backup purposes, and external analysis needs.

## Goals
- Enable data portability and backup for business continuity
- Support accounting software integration workflows
- Provide formatted exports for professional presentations
- Ensure data completeness and accuracy in exports
- Support various export formats for different use cases

## Success Metrics
- Export generation time < 30 seconds for standard datasets
- Export accuracy rate = 100%
- Export feature usage > 50% of businesses monthly
- File format compatibility > 95% with popular accounting software
- Export completion rate > 98%

## User Stories
- As a business owner, I want to export my quotes to CSV so I can analyze them in Excel
- As an accountant, I want to export invoice data to PDF for client records
- As a business owner, I want to export contact lists so I can use them in marketing tools
- As a business owner, I want to backup my data regularly for security
- As a staff member, I want to export job reports for project documentation

## Features

### Growth Phase (P2 - Advanced Features)
1. [Quote & Invoice Export](data-export/01-quote-export.md) - Export quotes and invoices in CSV/PDF formats
2. [Contact & Client Export](data-export/02-contact-export.md) - Export client and contact information
3. [Job & Service Export](data-export/03-job-export.md) - Export job records and service history
4. [Custom Export Builder](data-export/04-custom-export.md) - Configurable exports with field selection

## Technical Architecture

### Core Models
```ruby
# Export job tracking
class DataExport < ApplicationRecord
  belongs_to :business
  belongs_to :created_by, class_name: 'User'
  
  validates :export_type, :format, :status, presence: true
  
  enum export_type: {
    quotes: 0,
    contacts: 1,
    jobs: 2,
    invoices: 3,
    payments: 4,
    custom: 5
  }
  
  enum format: { csv: 0, pdf: 1, excel: 2 }
  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }
  
  # Store export parameters and file information
  validates :parameters, presence: true
  
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
end
```

### Export Service
```ruby
class DataExportService
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
    when 'contacts'
      export_contacts
    when 'jobs'
      export_jobs
    when 'invoices'
      export_invoices
    end
  end
  
  private
  
  def export_quotes
    quotes = @business.quotes.includes(:client, :quote_line_items)
    quotes = apply_date_filter(quotes) if @parameters[:date_range]
    quotes = apply_status_filter(quotes) if @parameters[:status]
    
    case @format
    when 'csv'
      generate_quotes_csv(quotes)
    when 'pdf'
      generate_quotes_pdf(quotes)
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
        'Notes'
      ]
      
      quotes.each do |quote|
        csv << [
          quote.id,
          quote.client_name,
          quote.client_email,
          quote.created_at.strftime('%Y-%m-%d'),
          quote.status.humanize,
          quote.total_amount,
          quote.quote_line_items.map(&:service_name).join('; '),
          quote.notes
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
        quote.client_name,
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
  
  def export_contacts
    contacts = @business.clients.includes(:quotes, :appointments)
    
    case @format
    when 'csv'
      generate_contacts_csv(contacts)
    when 'excel'
      generate_contacts_excel(contacts)
    end
  end
  
  def generate_contacts_csv(contacts)
    CSV.generate(headers: true) do |csv|
      csv << [
        'Name',
        'Email',
        'Phone',
        'Address',
        'Total Quotes',
        'Total Revenue',
        'Last Contact',
        'Customer Since'
      ]
      
      contacts.each do |contact|
        csv << [
          contact.name,
          contact.email,
          contact.phone,
          contact.full_address,
          contact.quotes.count,
          contact.quotes.accepted.sum(:total_amount),
          contact.quotes.maximum(:created_at)&.strftime('%Y-%m-%d'),
          contact.created_at.strftime('%Y-%m-%d')
        ]
      end
    end
  end
  
  def apply_date_filter(relation)
    return relation unless @parameters[:start_date] && @parameters[:end_date]
    
    start_date = Date.parse(@parameters[:start_date])
    end_date = Date.parse(@parameters[:end_date])
    
    relation.where(created_at: start_date..end_date)
  end
  
  def apply_status_filter(relation)
    return relation unless @parameters[:status].present?
    
    relation.where(status: @parameters[:status])
  end
end
```

### Background Job
```ruby
class DataExportJob < ApplicationJob
  queue_as :exports
  
  def perform(export_id)
    export = DataExport.find(export_id)
    export.update!(status: :processing)
    
    begin
      service = DataExportService.new(
        export.business,
        export.export_type,
        export.format,
        export.parameters
      )
      
      file_content = service.generate
      
      # Create temporary file
      temp_file = Tempfile.new([export.export_type, ".#{export.format}"])
      temp_file.write(file_content)
      temp_file.rewind
      
      # Attach file to export record
      export.export_file.attach(
        io: temp_file,
        filename: "#{export.export_type}_#{Date.current.strftime('%Y%m%d')}.#{export.format}",
        content_type: content_type_for_format(export.format)
      )
      
      export.update!(
        status: :completed,
        completed_at: Time.current,
        file_size: temp_file.size
      )
      
      # Send notification to user
      ExportCompletedMailer.notify(export).deliver_now
      
    rescue => e
      export.update!(
        status: :failed,
        error_message: e.message
      )
      Rails.logger.error "Export failed: #{e.message}"
    ensure
      temp_file&.close
      temp_file&.unlink
    end
  end
  
  private
  
  def content_type_for_format(format)
    case format
    when 'csv'
      'text/csv'
    when 'pdf'
      'application/pdf'
    when 'excel'
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    end
  end
end
```

## Integration Points
- Quote Management (quote data exports)
- Client Management (contact data exports)
- Job Management (service records exports)
- Payment Processing (financial data exports)
- Email System (export completion notifications)

## Security Considerations
- Ensure business scoping for all exported data
- Implement secure file storage with time-limited access
- Audit export activities for compliance
- Validate export parameters to prevent data leakage
- Encrypt sensitive data in export files

## Growth Phase Scope (P2 Priority)
**Included in Growth Phase:**
- CSV and PDF export formats
- 4 core export types (quotes, contacts, jobs, invoices)
- Basic filtering by date range and status
- Automated export completion notifications

**Future Enhancements:**
- Excel format with advanced formatting
- Scheduled recurring exports
- Custom field inclusion in exports
- API endpoint for programmatic exports

## Technical Implementation Notes
```ruby
# Controller for export management
class Admin::ExportsController < Admin::BaseController
  def create
    export = current_business.data_exports.create!(
      export_type: params[:export_type],
      format: params[:format],
      parameters: export_params,
      created_by: current_user,
      status: :pending
    )
    
    DataExportJob.perform_later(export.id)
    
    redirect_to admin_exports_path, notice: 'Export started. You will receive an email when complete.'
  end
  
  def index
    @exports = current_business.data_exports
      .includes(:created_by)
      .order(created_at: :desc)
      .page(params[:page])
  end
  
  def download
    export = current_business.data_exports.find(params[:id])
    
    if export.completed? && export.export_file.attached?
      redirect_to export.download_url
    else
      redirect_to admin_exports_path, alert: 'Export not ready for download.'
    end
  end
  
  private
  
  def export_params
    params.permit(:start_date, :end_date, :status, fields: [])
  end
end

# Migration for data exports
class CreateDataExports < ActiveRecord::Migration[8.0]
  def change
    create_table :data_exports do |t|
      t.references :business, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :export_type, null: false
      t.integer :format, null: false
      t.integer :status, default: 0
      t.json :parameters
      t.datetime :completed_at
      t.bigint :file_size
      t.text :error_message
      
      t.timestamps
    end
    
    add_index :data_exports, [:business_id, :created_at]
    add_index :data_exports, [:business_id, :export_type]
  end
end
```

## Export UI Interface
```erb
<!-- Export configuration form -->
<div class="export-form">
  <%= form_with url: admin_exports_path, method: :post, class: 'space-y-4' do |form| %>
    <div class="form-group">
      <label class="block text-sm font-medium">Export Type</label>
      <%= form.select :export_type, 
          options_for_select([
            ['Quotes', 'quotes'],
            ['Contacts', 'contacts'],
            ['Jobs', 'jobs'],
            ['Invoices', 'invoices']
          ]), 
          {}, 
          { class: 'mt-1 block w-full border-gray-300 rounded-md' } %>
    </div>
    
    <div class="form-group">
      <label class="block text-sm font-medium">Format</label>
      <%= form.select :format,
          options_for_select([
            ['CSV', 'csv'],
            ['PDF', 'pdf']
          ]),
          {},
          { class: 'mt-1 block w-full border-gray-300 rounded-md' } %>
    </div>
    
    <div class="form-group grid grid-cols-2 gap-4">
      <div>
        <label class="block text-sm font-medium">Start Date</label>
        <%= form.date_field :start_date, class: 'mt-1 block w-full border-gray-300 rounded-md' %>
      </div>
      <div>
        <label class="block text-sm font-medium">End Date</label>
        <%= form.date_field :end_date, value: Date.current, class: 'mt-1 block w-full border-gray-300 rounded-md' %>
      </div>
    </div>
    
    <%= form.submit 'Generate Export', class: 'w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700' %>
  <% end %>
</div>
```

## Dependencies
- Background Job Processing (Sidekiq)
- File Storage (Active Storage)
- PDF Generation (Prawn gem)
- Email System (export notifications)

## Estimate
- All Features: 15 story points (1.5 weeks)
- Note: This is a Growth Phase epic, not included in MVP
